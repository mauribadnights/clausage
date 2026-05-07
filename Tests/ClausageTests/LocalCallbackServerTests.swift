import XCTest
@testable import Clausage

final class LocalCallbackServerTests: XCTestCase {

    func testStartBindsToLoopbackAndExposesURL() async throws {
        let server = try LocalCallbackServer(path: "/callback")
        let url = try await server.start()

        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.path, "/callback")
        XCTAssertNotNil(url.port, "Bound port should be reflected in redirectURL")
        XCTAssertGreaterThan(url.port ?? 0, 0)

        server.cancel()
    }

    func testReceivesQueryParametersAndShutsDown() async throws {
        let server = try LocalCallbackServer(path: "/callback")
        let url = try await server.start()

        // Drive the callback in parallel with the wait.
        async let callbackTask: LocalCallbackServer.CallbackParams = server.waitForCallback(timeout: 5)

        // Hit the server with a synthetic OAuth redirect.
        let target = URL(string: "\(url.absoluteString)?code=abc123&state=xyz789")!
        let request = URLRequest(url: target)
        _ = try? await URLSession.shared.data(for: request)

        let params = try await callbackTask
        XCTAssertEqual(params.value(for: "code"), "abc123")
        XCTAssertEqual(params.value(for: "state"), "xyz789")
    }

    func testTimeoutFiresWhenNoRedirect() async throws {
        let server = try LocalCallbackServer(path: "/callback")
        _ = try await server.start()
        do {
            _ = try await server.waitForCallback(timeout: 0.5)
            XCTFail("Should have timed out")
        } catch let err as LocalCallbackServer.ServerError {
            if case .timeout = err {
                // expected
            } else {
                XCTFail("Wrong error: \(err)")
            }
        }
    }

    func testIgnoresUnrelatedPaths() async throws {
        let server = try LocalCallbackServer(path: "/callback")
        let url = try await server.start()

        async let callbackTask: () = {
            do {
                _ = try await server.waitForCallback(timeout: 2)
                XCTFail("Should not have resolved on /favicon.ico")
            } catch {
                // timeout / malformed expected
            }
        }()

        // Hit the wrong path — server should ignore (won't fulfill the continuation,
        // we'll get timeout instead).
        let badURL = URL(string: "http://127.0.0.1:\(url.port!)/favicon.ico")!
        _ = try? await URLSession.shared.data(for: URLRequest(url: badURL))

        await callbackTask
    }
}
