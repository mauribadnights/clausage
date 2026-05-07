import Foundation

/// File-based persistence for OAuth tokens.
///
/// Replaces keychain storage with a plain JSON file in Application Support. We prefer
/// a file over the keychain for two reasons:
/// 1. Reliability — the keychain prompts when accessed by an unsigned/ad-hoc binary,
///    and access can fail post-wake-from-sleep. A file with 0600 permissions is
///    bound to the user account and works without prompts.
/// 2. Independence — Clausage owns its own refresh token (originally obtained via
///    its own browser OAuth flow), so it doesn't need to read Claude Code's keychain
///    item every time.
///
/// File path: `~/Library/Application Support/Clausage/oauth.json`
/// Permissions: 0600 (user-only read/write).
enum CredentialStore {
    private static let fileName = "oauth.json"
    private static let folderName = "Clausage"

    // MARK: - Public API

    static func load() -> StoredCredentials? {
        guard let url = fileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder.iso8601.decode(StoredCredentials.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    static func save(_ credentials: StoredCredentials) throws {
        guard let url = fileURL() else {
            throw CredentialStoreError.locationUnavailable
        }
        try ensureDirectory(at: url.deletingLastPathComponent())

        let data = try JSONEncoder.iso8601Pretty.encode(credentials)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try setOwnerOnlyPermissions(at: url)
    }

    static func delete() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func exists() -> Bool {
        guard let url = fileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Internal

    private static func fileURL() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return base.appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private static func setOwnerOnlyPermissions(at url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

// MARK: - Models

/// Persistable credential bundle. Source helps the migration UI explain how
/// the user got authenticated (clean browser flow vs imported from Claude Code).
struct StoredCredentials: Codable, Equatable {
    enum Source: String, Codable {
        case browser            // Clausage ran its own OAuth flow
        case claudeCodeImport   // bootstrapped by reading Claude Code's keychain once
    }

    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let source: Source
    let obtainedAt: Date

    init(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        source: Source,
        obtainedAt: Date = Date()
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.source = source
        self.obtainedAt = obtainedAt
    }
}

enum CredentialStoreError: Error {
    case locationUnavailable
}

// MARK: - JSON helpers

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension JSONEncoder {
    static let iso8601Pretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
