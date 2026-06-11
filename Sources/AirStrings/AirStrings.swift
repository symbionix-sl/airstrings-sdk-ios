import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the AirStrings SDK.
///
/// An `@Observable` class that fetches, verifies, caches, and exposes remotely-managed
/// localized strings. Inject into SwiftUI via `.environment(\.airStrings, airStrings)`.
///
/// String access via subscript returns the key name as fallback when no bundle is loaded:
/// ```swift
/// Text(strings["onboarding.welcome_title"])
/// ```
@MainActor
@Observable
public final class AirStrings {

  // MARK: - Observed state (triggers view updates)

  /// The active string dictionary. Raw values keyed by string ID.
  var strings: [String: String] = [:]

  /// Current active BCP 47 locale.
  public var currentLocale: String = "en"

  /// True after first bundle loaded (from cache or network).
  public private(set) var isReady: Bool = false

  /// Current bundle revision, 0 if no bundle.
  public private(set) var revision: Int = 0

  // MARK: - Not observed (internal machinery)

  /// Internal format metadata, keyed by string ID. Not observed.
  @ObservationIgnored var stringEntries: [String: StringEntry] = [:]

  @ObservationIgnored private var configuration: AirStringsConfiguration
  @ObservationIgnored private var fetcher: BundleFetcher?
  @ObservationIgnored private let verifier: BundleVerifier
  @ObservationIgnored private let store: BundleStore
  @ObservationIgnored private var cachedETags: [String: String] = [:]
  @ObservationIgnored private var cachedRevisions: [String: Int] = [:]
  @ObservationIgnored private var activeRefreshTask: Task<Void, Never>?
  @ObservationIgnored nonisolated(unsafe) private var foregroundObserver: (any NSObjectProtocol)?
  @ObservationIgnored private let logger = Logger(subsystem: "com.airstrings.sdk", category: "AirStrings")
  @ObservationIgnored private let isPlaceholder: Bool

  /// Called when strings update mid-session. Receives locale and new revision.
  @ObservationIgnored public var onStringsUpdated: ((_ locale: String, _ revision: Int) -> Void)?

  // MARK: - Shared instance

  /// The shared instance, available after calling `configure(_:)`.
  /// Accessing before configuration is a programmer error.
  public private(set) static var shared: AirStrings!

  /// Configures the shared instance. Must be called exactly once, typically in app launch.
  public static func configure(_ configuration: AirStringsConfiguration) {
    precondition(shared == nil, "AirStrings.configure(_:) must be called exactly once")
    shared = AirStrings(configuration: configuration)
  }

  // MARK: - Public API

  /// Returns the localized string for the given key, or the key itself as fallback.
  public subscript(_ key: String) -> String {
    strings[key] ?? key
  }

  /// Returns a formatted string for the given key.
  ///
  /// - For `"text"` format strings: returns the value as-is, ignoring `args`.
  /// - For `"icu"` format strings: formats the ICU MessageFormat pattern with the given arguments.
  /// - On formatting failure or missing key: returns the raw value or the key name as fallback.
  public func string(_ key: String, args: [String: Any]) -> String {
    guard let entry = stringEntries[key] else { return key }

    switch entry.format {
    case .text:
      return entry.value
    case .icu:
      return ICUMessageFormat.format(entry.value, locale: currentLocale, args: args)
    }
  }

  /// Creates a new AirStrings instance and immediately loads cached strings + fetches fresh ones.
  public convenience init(configuration: AirStringsConfiguration) {
    self.init(configuration: configuration, store: BundleStore())
  }

  init(configuration: AirStringsConfiguration, store: BundleStore) {
    self.isPlaceholder = false
    self.configuration = configuration
    self.verifier = BundleVerifier(publicKeys: configuration.publicKeys)
    self.store = store
    self.currentLocale = configuration.locale.resolved

    // If baseURL already set (testing), create fetcher immediately
    if let baseURL = configuration.baseURL {
      self.fetcher = BundleFetcher(baseURL: baseURL)
    }

    loadLocalCandidates(for: currentLocale)
    observeForeground()

    Task { [weak self] in
      await self?.ensureFetcher()
      await self?.refresh()
    }
  }

  deinit {
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Switches to a new locale. Loads cached bundle instantly if available,
  /// then fetches the latest from CDN in the background.
  public func setLocale(_ bcp47: String) async {
    currentLocale = bcp47

    await ensureFetcher()

    loadLocalCandidates(for: bcp47)

    // Bypass refresh coalescing — if a refresh for the previous locale is
    // in flight, awaiting it via refresh() would return without ever
    // fetching the new locale. Call performRefresh() directly to guarantee
    // the new locale is fetched.
    await performRefresh()
  }

  /// Fetches the latest bundle from CDN for the current locale.
  /// Uses ETag for conditional requests. Silent on network errors.
  /// Coalesces concurrent calls — if a refresh is already in flight, callers await the existing one.
  public func refresh() async {
    guard !isPlaceholder else { return }

    if let existing = activeRefreshTask {
      await existing.value
      return
    }

    let task = Task {
      await self.performRefresh()
    }
    activeRefreshTask = task
    await task.value
    activeRefreshTask = nil
  }

  private func performRefresh() async {
    await ensureFetcher()

    guard let fetcher else {
      logger.error("Fetcher unavailable after bootstrap")
      return
    }

    let locale = currentLocale

    do {
      let result = try await fetcher.fetch(
        organizationId: configuration.organizationId,
        projectId: configuration.projectId,
        environmentId: configuration.environmentId,
        locale: locale,
        ifNoneMatch: cachedETags[locale]
      )

      switch result {
      case .notModified:
        logger.info("Bundle up to date: \(locale)")
        if !isReady { isReady = true }

      case .success(let data, let etag):
        guard let bundle = decodeBundle(from: data) else { return }

        do {
          try verifier.verify(bundle)
        } catch {
          logger.error("Signature verification failed: \(error)")
          return
        }

        // Anti-downgrade: don't replace newer revision with older for same locale
        let knownRevision = cachedRevisions[bundle.locale] ?? 0
        if bundle.revision < knownRevision {
          logger.warning("Ignoring stale bundle: rev \(bundle.revision) < current \(knownRevision) for \(bundle.locale)")
          return
        }

        store.save(data, projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale, etag: etag)
        cachedETags[locale] = etag

        // Only apply if locale hasn't changed during fetch
        if locale == currentLocale {
          applyBundle(bundle)
          isReady = true
          onStringsUpdated?(locale, bundle.revision)
        }
      }
    } catch {
      logger.error("Fetch failed for \(locale): \(error)")
      if !isReady {
        // If we have a cached bundle, mark as ready
        if store.load(projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale) != nil {
          isReady = true
        }
        // else: no cache + no network → isReady stays false, keys return as fallback
      }
    }
  }

  // MARK: - Placeholder

  /// Non-functional instance used as SwiftUI EnvironmentValues default.
  nonisolated static let placeholder: AirStrings = {
    let instance = AirStrings(placeholder: ())
    return instance
  }()

  nonisolated private init(placeholder _: Void) {
    self.isPlaceholder = true
    self.configuration = .placeholder
    self.fetcher = BundleFetcher(baseURL: URL(string: "https://localhost")!)
    self.verifier = BundleVerifier(publicKeys: [])
    self.store = BundleStore()
  }

  // MARK: - Bootstrap

  /// Discovers CDN base URL via bootstrap endpoint.
  /// If baseURL is already set (testing), skips the network call.
  /// Falls back to https://cdn.airstrings.com on any failure.
  private func bootstrap() async -> URL {
    if let baseURL = configuration.baseURL {
      return baseURL
    }

    let base = configuration.apiBaseURL.absoluteString.hasSuffix("/")
      ? configuration.apiBaseURL.absoluteString
      : configuration.apiBaseURL.absoluteString + "/"
    let bootstrapURL = URL(string: base + "v1/sdk/bootstrap")!
    do {
      let (data, _) = try await URLSession.shared.data(from: bootstrapURL)
      let response = try JSONDecoder().decode(BootstrapResponse.self, from: data)
      guard let url = URL(string: response.cdnBaseURL) else {
        throw URLError(.badURL)
      }
      return url
    } catch {
      logger.warning("Bootstrap failed, falling back to default CDN URL: \(error)")
      return URL(string: "https://cdn.airstrings.com")!
    }
  }

  /// Ensures fetcher is initialized, running bootstrap if needed.
  private func ensureFetcher() async {
    guard fetcher == nil else { return }
    let baseURL = await bootstrap()
    configuration.baseURL = baseURL
    fetcher = BundleFetcher(baseURL: baseURL)
  }

  private struct BootstrapResponse: Decodable {
    let cdnBaseURL: String

    enum CodingKeys: String, CodingKey {
      case cdnBaseURL = "cdn_base_url"
    }
  }

  // MARK: - Private

  private func applyBundle(_ bundle: StringBundle) {
    stringEntries = bundle.strings
    strings = bundle.strings.mapValues { $0.value }
    revision = bundle.revision
    cachedRevisions[bundle.locale] = bundle.revision
  }

  private func loadLocalCandidates(for locale: String) {
    var cachedCandidate: (bundle: StringBundle, etag: String?)?
    if let cached = store.load(projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale) {
      if let bundle = decodeBundle(from: cached.data) {
        do {
          try verifier.verify(bundle)
          cachedCandidate = (bundle, cached.etag)
        } catch {
          logger.error("Cached bundle verification failed for \(locale), clearing cache")
          store.delete(projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale)
        }
      } else {
        store.delete(projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale)
      }
    }

    let seedCandidate = loadSeedCandidate(for: locale)
    let highestKnownRevision = max(cachedCandidate?.bundle.revision ?? Int.min, cachedRevisions[locale] ?? Int.min)

    if let seedCandidate, seedCandidate.bundle.revision > highestKnownRevision {
      store.save(seedCandidate.data, projectId: configuration.projectId, environmentId: configuration.environmentId, locale: locale, etag: nil)
      cachedETags[locale] = nil
      applyBundle(seedCandidate.bundle)
      isReady = true
    } else if let cachedCandidate {
      applyBundle(cachedCandidate.bundle)
      cachedETags[locale] = cachedCandidate.etag
      isReady = true
    }
  }

  private func loadSeedCandidate(for locale: String) -> (bundle: StringBundle, data: Data)? {
    guard configuration.isSeedingEnabled else { return nil }

    guard let url = configuration.seedBundle.url(
      forResource: locale,
      withExtension: "json",
      subdirectory: configuration.seedSubdirectory
    ) else {
      return nil
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      logger.error("Seed bundle rejected for \(locale): unreadable resource: \(error)")
      return nil
    }

    guard let bundle = decodeBundle(from: data) else {
      logger.error("Seed bundle rejected for \(locale): decoding failed")
      return nil
    }

    do {
      try verifier.verify(bundle)
      guard bundle.projectId == configuration.projectId else {
        throw AirStringsError.seedProjectMismatch(expected: configuration.projectId, found: bundle.projectId)
      }
      guard bundle.locale == locale else {
        throw AirStringsError.seedLocaleMismatch(expected: locale, found: bundle.locale)
      }
      return (bundle, data)
    } catch {
      logger.error("Seed bundle rejected for \(locale): \(error)")
      return nil
    }
  }

  private func decodeBundle(from data: Data) -> StringBundle? {
    do {
      return try JSONDecoder().decode(StringBundle.self, from: data)
    } catch {
      logger.error("Bundle decoding failed: \(error)")
      return nil
    }
  }

  private func observeForeground() {
#if canImport(UIKit)
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { await self.refresh() }
    }
#endif
  }
}
