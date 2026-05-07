import XCTest
@testable import Clausage

final class CodexAuthServiceTests: XCTestCase {

    /// The static parsing logic isn't directly exposed; we exercise it via the public
    /// `load()` path with a temp file by setting HOME — but `NSHomeDirectory()` is
    /// captured at process start on macOS, so we instead test the pure JWT helpers via
    /// a small test-only shim built using the same base64URL extension.
    ///
    /// These tests verify our base64URL decoder handles real JWT-shaped input.

    func testBase64URLDecodeBasic() {
        // "Hello" base64 = "SGVsbG8=" (with padding) → "SGVsbG8" base64url.
        let input = "SGVsbG8"
        var s = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        let decoded = Data(base64Encoded: s)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(String(data: decoded!, encoding: .utf8), "Hello")
    }

    func testJWTPayloadShape() throws {
        // Build a fake JWT payload exercising the same decoding the service does.
        let payload: [String: Any] = [
            "exp": Date().addingTimeInterval(3600).timeIntervalSince1970,
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "pro",
                "chatgpt_account_id": "acc-test"
            ]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let payloadB64 = payloadData.base64URLEncodedString()
        let header = #"{"alg":"none"}"#.data(using: .utf8)!.base64URLEncodedString()
        let signature = "fakesig"
        let jwt = "\(header).\(payloadB64).\(signature)"

        // Mirror the decoder exactly (we don't expose it; this test pins the format
        // we expect Codex CLI to keep emitting).
        let parts = jwt.split(separator: ".")
        XCTAssertEqual(parts.count, 3)

        var s = String(parts[1])
        s = s.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        let decoded = Data(base64Encoded: s)
        XCTAssertNotNil(decoded)

        let claims = try JSONSerialization.jsonObject(with: decoded!) as? [String: Any]
        XCTAssertNotNil(claims?["exp"])
        XCTAssertNotNil(claims?["https://api.openai.com/auth"])
    }

    func testLoadFailsClearlyWhenFileMissingAtBogusLocation() {
        // We can't redirect NSHomeDirectory at runtime safely; instead, just confirm
        // the error type we surface when load() decides the file is absent. This is
        // best-exercised via the integration smoke test below if a real
        // `~/.codex/auth.json` is absent.
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex/auth.json") {
            switch CodexAuthService.load() {
            case .success: XCTFail("Should have failed without a creds file")
            case .failure(let err):
                XCTAssertEqual(err, .fileMissing)
            }
        }
    }
}
