import Testing
import Foundation
@testable import AirStrings

@Suite("BundleStore")
final class BundleStoreTests {
  let store: BundleStore
  let tempDir: URL

  init() {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("AirStringsTests-\(UUID().uuidString)", isDirectory: true)
    store = BundleStore(baseDirectory: tempDir)
  }

  deinit {
    try? FileManager.default.removeItem(at: tempDir)
  }

  @Test func saveAndLoadRoundTrip() {
    let data = Data(#"{"format_version":1,"strings":{}}"#.utf8)
    store.save(data, projectId: "proj_test12345678", locale: "en", etag: "\"rev:42\"")

    let loaded = store.load(projectId: "proj_test12345678", locale: "en")
    #expect(loaded != nil)
    #expect(loaded?.data == data)
    #expect(loaded?.etag == "\"rev:42\"")
  }

  @Test func loadReturnsNilWhenEmpty() {
    let loaded = store.load(projectId: "proj_nonexistent", locale: "en")
    #expect(loaded == nil)
  }

  @Test func perLocaleIsolation() {
    let enData = Data(#"{"locale":"en"}"#.utf8)
    let frData = Data(#"{"locale":"fr"}"#.utf8)

    store.save(enData, projectId: "proj_test12345678", locale: "en", etag: "\"en:1\"")
    store.save(frData, projectId: "proj_test12345678", locale: "fr", etag: "\"fr:1\"")

    let enLoaded = store.load(projectId: "proj_test12345678", locale: "en")
    let frLoaded = store.load(projectId: "proj_test12345678", locale: "fr")

    #expect(enLoaded?.data == enData)
    #expect(frLoaded?.data == frData)
    #expect(enLoaded?.etag == "\"en:1\"")
    #expect(frLoaded?.etag == "\"fr:1\"")
  }

  @Test func deleteRemovesCache() {
    let data = Data(#"{"test":true}"#.utf8)
    store.save(data, projectId: "proj_test12345678", locale: "en", etag: nil)

    #expect(store.load(projectId: "proj_test12345678", locale: "en") != nil)

    store.delete(projectId: "proj_test12345678", locale: "en")

    #expect(store.load(projectId: "proj_test12345678", locale: "en") == nil)
  }

  @Test func saveWithNilEtag() {
    let data = Data(#"{"test":true}"#.utf8)
    store.save(data, projectId: "proj_test12345678", locale: "en", etag: nil)

    let loaded = store.load(projectId: "proj_test12345678", locale: "en")
    #expect(loaded != nil)
    #expect(loaded?.data == data)
    #expect(loaded?.etag == nil)
  }

  @Test func overwriteExistingCache() {
    let data1 = Data(#"{"revision":1}"#.utf8)
    let data2 = Data(#"{"revision":2}"#.utf8)

    store.save(data1, projectId: "proj_test12345678", locale: "en", etag: "\"v1\"")
    store.save(data2, projectId: "proj_test12345678", locale: "en", etag: "\"v2\"")

    let loaded = store.load(projectId: "proj_test12345678", locale: "en")
    #expect(loaded?.data == data2)
    #expect(loaded?.etag == "\"v2\"")
  }

  @Test func corruptedMetadataStillReturnsData() throws {
    let data = Data(#"{"test":true}"#.utf8)
    store.save(data, projectId: "proj_test12345678", locale: "en", etag: "\"valid\"")

    let metadataURL = tempDir
      .appendingPathComponent("proj_test12345678")
      .appendingPathComponent("en")
      .appendingPathComponent("metadata.json")
    try Data("corrupted".utf8).write(to: metadataURL)

    let loaded = store.load(projectId: "proj_test12345678", locale: "en")
    #expect(loaded != nil)
    #expect(loaded?.data == data)
    #expect(loaded?.etag == nil)
  }
}
