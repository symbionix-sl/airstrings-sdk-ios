import XCTest
@testable import AirStrings

final class BundleStoreTests: XCTestCase {
    private var store: BundleStore!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirStringsTests-\(UUID().uuidString)", isDirectory: true)
        store = BundleStore(baseDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let data = Data(#"{"format_version":1,"strings":{}}"#.utf8)
        store.save(data, projectId: "proj_test12345678", locale: "en", etag: "\"rev:42\"")

        let loaded = store.load(projectId: "proj_test12345678", locale: "en")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.data, data)
        XCTAssertEqual(loaded?.etag, "\"rev:42\"")
    }

    func testLoadReturnsNilWhenEmpty() {
        let loaded = store.load(projectId: "proj_nonexistent", locale: "en")
        XCTAssertNil(loaded)
    }

    func testPerLocaleIsolation() {
        let enData = Data(#"{"locale":"en"}"#.utf8)
        let frData = Data(#"{"locale":"fr"}"#.utf8)

        store.save(enData, projectId: "proj_test12345678", locale: "en", etag: "\"en:1\"")
        store.save(frData, projectId: "proj_test12345678", locale: "fr", etag: "\"fr:1\"")

        let enLoaded = store.load(projectId: "proj_test12345678", locale: "en")
        let frLoaded = store.load(projectId: "proj_test12345678", locale: "fr")

        XCTAssertEqual(enLoaded?.data, enData)
        XCTAssertEqual(frLoaded?.data, frData)
        XCTAssertEqual(enLoaded?.etag, "\"en:1\"")
        XCTAssertEqual(frLoaded?.etag, "\"fr:1\"")
    }

    func testDeleteRemovesCache() {
        let data = Data(#"{"test":true}"#.utf8)
        store.save(data, projectId: "proj_test12345678", locale: "en", etag: nil)

        XCTAssertNotNil(store.load(projectId: "proj_test12345678", locale: "en"))

        store.delete(projectId: "proj_test12345678", locale: "en")

        XCTAssertNil(store.load(projectId: "proj_test12345678", locale: "en"))
    }

    func testSaveWithNilEtag() {
        let data = Data(#"{"test":true}"#.utf8)
        store.save(data, projectId: "proj_test12345678", locale: "en", etag: nil)

        let loaded = store.load(projectId: "proj_test12345678", locale: "en")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.data, data)
        XCTAssertNil(loaded?.etag)
    }

    func testOverwriteExistingCache() {
        let data1 = Data(#"{"revision":1}"#.utf8)
        let data2 = Data(#"{"revision":2}"#.utf8)

        store.save(data1, projectId: "proj_test12345678", locale: "en", etag: "\"v1\"")
        store.save(data2, projectId: "proj_test12345678", locale: "en", etag: "\"v2\"")

        let loaded = store.load(projectId: "proj_test12345678", locale: "en")
        XCTAssertEqual(loaded?.data, data2)
        XCTAssertEqual(loaded?.etag, "\"v2\"")
    }

    func testCorruptedMetadataStillReturnsData() {
        let data = Data(#"{"test":true}"#.utf8)
        store.save(data, projectId: "proj_test12345678", locale: "en", etag: "\"valid\"")

        // Corrupt the metadata file
        let metadataURL = tempDir
            .appendingPathComponent("proj_test12345678")
            .appendingPathComponent("en")
            .appendingPathComponent("metadata.json")
        try? Data("corrupted".utf8).write(to: metadataURL)

        let loaded = store.load(projectId: "proj_test12345678", locale: "en")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.data, data)
        XCTAssertNil(loaded?.etag) // Metadata corrupted, etag falls back to nil
    }
}
