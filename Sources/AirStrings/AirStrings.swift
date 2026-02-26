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
  
  /// The active string dictionary. Accessed via subscript.
  var strings: [String: String] = [:]
  
  /// Current active BCP 47 locale.
  public var currentLocale: String = "en"
  
  /// True after first bundle loaded (from cache or network).
  public private(set) var isReady: Bool = false
  
  /// Current bundle revision, 0 if no bundle.
  public private(set) var revision: Int = 0
  
  // MARK: - Not observed (internal machinery)
  
  @ObservationIgnored private let configuration: AirStringsConfiguration
  @ObservationIgnored private let fetcher: BundleFetcher
  @ObservationIgnored private let verifier: BundleVerifier
  @ObservationIgnored private let store: BundleStore
  @ObservationIgnored private var cachedETags: [String: String] = [:]
  @ObservationIgnored nonisolated(unsafe) private var foregroundObserver: (any NSObjectProtocol)?
  @ObservationIgnored private let logger = Logger(subsystem: "com.airstrings.sdk", category: "AirStrings")
  @ObservationIgnored private let isPlaceholder: Bool
  
  /// Called when strings update mid-session. Receives locale and new revision.
  @ObservationIgnored public var onStringsUpdated: ((_ locale: String, _ revision: Int) -> Void)?
  
  // MARK: - Public API
  
  /// Returns the localized string for the given key, or the key itself as fallback.
  public subscript(_ key: String) -> String {
    strings[key] ?? key
  }
  
  /// Creates a new AirStrings instance and immediately loads cached strings + fetches fresh ones.
  public init(configuration: AirStringsConfiguration) {
    self.isPlaceholder = false
    self.configuration = configuration
    self.fetcher = BundleFetcher(baseURL: configuration.baseURL)
    self.verifier = BundleVerifier(publicKeys: configuration.publicKeys)
    self.store = BundleStore()
    self.currentLocale = configuration.locale.resolved
    
    loadCachedBundle()
    observeForeground()
    
    Task { [weak self] in
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
    
    // Try loading cached bundle for new locale
    if let cached = store.load(projectId: configuration.projectId, locale: bcp47) {
      if let bundle = decodeBundle(from: cached.data) {
        do {
          try verifier.verify(bundle)
          strings = bundle.strings
          revision = bundle.revision
          cachedETags[bcp47] = cached.etag
        } catch {
          logger.error("Cached bundle verification failed for \(bcp47), clearing cache")
          store.delete(projectId: configuration.projectId, locale: bcp47)
          strings = [:]
          revision = 0
        }
      }
    } else {
      strings = [:]
      revision = 0
    }
    
    await refresh()
  }
  
  /// Fetches the latest bundle from CDN for the current locale.
  /// Uses ETag for conditional requests. Silent on network errors.
  public func refresh() async {
    guard !isPlaceholder else { return }
    
    let locale = currentLocale
    
    do {
      let result = try await fetcher.fetch(
        projectId: configuration.projectId,
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
        if bundle.locale == currentLocale && bundle.revision < revision {
          logger.warning("Ignoring stale bundle: rev \(bundle.revision) < current \(self.revision)")
          return
        }
        
        store.save(data, projectId: configuration.projectId, locale: locale, etag: etag)
        cachedETags[locale] = etag
        
        // Only apply if locale hasn't changed during fetch
        if locale == currentLocale {
          strings = bundle.strings
          revision = bundle.revision
          isReady = true
          onStringsUpdated?(locale, bundle.revision)
        }
      }
    } catch {
      logger.error("Fetch failed for \(locale): \(error)")
      if !isReady {
        // If we have a cached bundle, mark as ready
        if store.load(projectId: configuration.projectId, locale: locale) != nil {
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
    self.verifier = BundleVerifier(publicKeys: [:])
    self.store = BundleStore()
  }
  
  // MARK: - Private
  
  private func loadCachedBundle() {
    guard let cached = store.load(projectId: configuration.projectId, locale: currentLocale) else {
      return
    }
    
    guard let bundle = decodeBundle(from: cached.data) else {
      store.delete(projectId: configuration.projectId, locale: currentLocale)
      return
    }
    
    do {
      try verifier.verify(bundle)
      strings = bundle.strings
      revision = bundle.revision
      isReady = true
      cachedETags[currentLocale] = cached.etag
    } catch {
      logger.error("Cached bundle verification failed, clearing cache")
      store.delete(projectId: configuration.projectId, locale: currentLocale)
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
