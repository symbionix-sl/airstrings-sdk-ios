import Foundation
import os

struct CacheMetadata: Codable, Sendable {
    let etag: String?
    let cachedAt: String
}

final class BundleStore: Sendable {
    private let baseDirectory: URL
    private let logger = Logger(subsystem: "com.airstrings.sdk", category: "BundleStore")

    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            self.baseDirectory = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AirStrings", isDirectory: true)
        }
    }

    private func directory(projectId: String, locale: String) -> URL {
        baseDirectory
            .appendingPathComponent(projectId, isDirectory: true)
            .appendingPathComponent(locale, isDirectory: true)
    }

    func save(_ data: Data, projectId: String, locale: String, etag: String?) {
        let dir = directory(projectId: projectId, locale: locale)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent("bundle.json"))

            let metadata = CacheMetadata(
                etag: etag,
                cachedAt: ISO8601DateFormatter().string(from: Date())
            )
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: dir.appendingPathComponent("metadata.json"))
        } catch {
            logger.error("Failed to save cache: \(error)")
        }
    }

    func load(projectId: String, locale: String) -> (data: Data, etag: String?)? {
        let dir = directory(projectId: projectId, locale: locale)
        let bundleURL = dir.appendingPathComponent("bundle.json")

        guard let data = try? Data(contentsOf: bundleURL) else {
            return nil
        }

        let metadataURL = dir.appendingPathComponent("metadata.json")
        let etag: String?
        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(CacheMetadata.self, from: metadataData) {
            etag = metadata.etag
        } else {
            etag = nil
        }

        return (data: data, etag: etag)
    }

    func delete(projectId: String, locale: String) {
        let dir = directory(projectId: projectId, locale: locale)
        try? FileManager.default.removeItem(at: dir)
    }
}
