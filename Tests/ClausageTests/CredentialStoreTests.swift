import XCTest
@testable import Clausage

/// CredentialStore tests redirect storage to a unique temp file via
/// `CredentialStore.overrideURL` so the live app's token at
/// `~/Library/Application Support/Clausage/oauth.json` is never touched.
final class CredentialStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clausage-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        CredentialStore.overrideURL = tempDir.appendingPathComponent("oauth.json")
    }

    override func tearDown() {
        super.tearDown()
        CredentialStore.overrideURL = nil
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testRoundTrip() throws {
        let original = StoredCredentials(
            accessToken: "access-XYZ",
            refreshToken: "refresh-ABC",
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            source: .browser,
            obtainedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try CredentialStore.save(original)

        let loaded = CredentialStore.load()
        XCTAssertEqual(loaded?.accessToken, "access-XYZ")
        XCTAssertEqual(loaded?.refreshToken, "refresh-ABC")
        XCTAssertEqual(loaded?.source, .browser)
        XCTAssertEqual(loaded?.expiresAt, Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(loaded?.obtainedAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testDeleteRemovesFile() throws {
        let creds = StoredCredentials(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(), source: .claudeCodeImport
        )
        try CredentialStore.save(creds)
        XCTAssertTrue(CredentialStore.exists())
        CredentialStore.delete()
        XCTAssertFalse(CredentialStore.exists())
    }

    func testFileHasOwnerOnlyPermissions() throws {
        let creds = StoredCredentials(
            accessToken: "a", refreshToken: "r",
            expiresAt: Date(), source: .browser
        )
        try CredentialStore.save(creds)

        let url = CredentialStore.overrideURL!
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let perms = attrs[.posixPermissions] as? NSNumber else {
            XCTFail("Permissions attribute missing")
            return
        }
        XCTAssertEqual(perms.intValue, 0o600, "Token file must be readable only by the owner")
    }

    func testSourceClaudeCodeImport() throws {
        let creds = StoredCredentials(
            accessToken: "x", refreshToken: "y",
            expiresAt: Date(), source: .claudeCodeImport
        )
        try CredentialStore.save(creds)
        XCTAssertEqual(CredentialStore.load()?.source, .claudeCodeImport)
    }

    func testLoadReturnsNilWhenFileAbsent() {
        XCTAssertNil(CredentialStore.load())
        XCTAssertFalse(CredentialStore.exists())
    }

    func testLoadReturnsNilOnGarbageData() throws {
        try Data("not json at all".utf8).write(to: CredentialStore.overrideURL!)
        XCTAssertNil(CredentialStore.load())
    }
}
