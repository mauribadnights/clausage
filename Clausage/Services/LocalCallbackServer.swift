import Foundation
import Network

/// Minimal one-shot HTTP server that listens on `127.0.0.1:<ephemeral-port>` for the
/// OAuth provider's redirect, captures the query parameters, returns a friendly HTML
/// page to the user's browser, and shuts down.
///
/// Intentionally tiny: handles one request, then closes. No keep-alive, no routing.
/// Built on `Network.framework` (`NWListener`) so we don't pull in a server library.
///
/// Lifecycle:
/// ```
/// let server = try LocalCallbackServer(path: "/callback")
/// let url = try await server.start()         // bound on ephemeral port; URL contains it
/// // ... open browser to authorize URL using `url` as redirect_uri ...
/// let params = try await server.waitForCallback()
/// ```
final class LocalCallbackServer {
    enum ServerError: Error, LocalizedError {
        case bindFailed(Error)
        case timeout
        case malformedRequest
        case canceled
        case notStarted

        var errorDescription: String? {
            switch self {
            case .bindFailed(let err): return "Could not start local callback server: \(err.localizedDescription)"
            case .timeout: return "Timed out waiting for the browser to redirect back."
            case .malformedRequest: return "Received a malformed callback request."
            case .canceled: return "Authentication was canceled."
            case .notStarted: return "Callback server has not started yet."
            }
        }
    }

    /// Captured callback parameters.
    struct CallbackParams {
        let queryItems: [URLQueryItem]

        func value(for name: String) -> String? {
            queryItems.first { $0.name == name }?.value
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.clausage.oauth-callback")
    private let path: String

    private var startContinuation: CheckedContinuation<URL, Error>?
    private var startResolved = false

    private var callbackContinuation: CheckedContinuation<CallbackParams, Error>?
    private var callbackResolved = false
    private var timeoutTask: DispatchWorkItem?

    private(set) var redirectURL: URL?

    /// - Parameter path: the redirect path the provider will hit, e.g. `/callback`.
    /// - Parameter preferredPort: if non-nil, try this port first. If it's taken, falls
    ///   back to an ephemeral port.
    init(path: String = "/callback", preferredPort: UInt16? = nil) throws {
        self.path = path

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredInterfaceType = .loopback

        if let preferred = preferredPort, let endpoint = NWEndpoint.Port(rawValue: preferred) {
            do {
                self.listener = try NWListener(using: parameters, on: endpoint)
                return
            } catch {
                // fall through to ephemeral
            }
        }
        self.listener = try NWListener(using: parameters)
    }

    /// Bind the listener and resolve the redirect URL (loopback + bound port + path).
    /// Returns once the listener is in `.ready` state. Must be called before `waitForCallback`.
    @discardableResult
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            self.startContinuation = cont

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let port = self.listener.port?.rawValue,
                       let url = URL(string: "http://127.0.0.1:\(port)\(self.path)") {
                        self.redirectURL = url
                        self.resolveStart(.success(url))
                    } else {
                        self.resolveStart(.failure(ServerError.notStarted))
                    }
                case .failed(let error):
                    self.resolveStart(.failure(ServerError.bindFailed(error)))
                    self.fulfillCallback(with: .failure(ServerError.bindFailed(error)))
                case .cancelled:
                    self.fulfillCallback(with: .failure(ServerError.canceled))
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    /// Await the redirect. Returns once a request lands or the timeout fires.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> CallbackParams {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CallbackParams, Error>) in
            self.callbackContinuation = cont

            let work = DispatchWorkItem { [weak self] in
                self?.fulfillCallback(with: .failure(ServerError.timeout))
            }
            self.timeoutTask = work
            queue.asyncAfter(deadline: .now() + timeout, execute: work)
        }
    }

    func cancel() {
        fulfillCallback(with: .failure(ServerError.canceled))
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self = self else { return }

            if let error = error {
                self.fulfillCallback(with: .failure(ServerError.bindFailed(error)))
                connection.cancel()
                return
            }
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                self.fulfillCallback(with: .failure(ServerError.malformedRequest))
                connection.cancel()
                return
            }

            let params = self.parseRequestLine(request)
            self.respond(to: connection, success: params != nil)
            if let params = params {
                self.fulfillCallback(with: .success(params))
            } else {
                self.fulfillCallback(with: .failure(ServerError.malformedRequest))
            }
        }
    }

    private func parseRequestLine(_ raw: String) -> CallbackParams? {
        let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? raw
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              parts[0] == "GET" else { return nil }

        let pathAndQuery = String(parts[1])
        // Only accept hits to the configured path, ignore favicon etc.
        let onlyPath = pathAndQuery.split(separator: "?", maxSplits: 1).first.map(String.init) ?? pathAndQuery
        guard onlyPath == self.path else { return nil }

        guard let comps = URLComponents(string: "http://127.0.0.1\(pathAndQuery)") else {
            return nil
        }
        return CallbackParams(queryItems: comps.queryItems ?? [])
    }

    private func respond(to connection: NWConnection, success: Bool) {
        let body: String = success ? Self.successHTML : Self.failureHTML
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Continuation helpers

    private func resolveStart(_ result: Result<URL, Error>) {
        queue.async { [weak self] in
            guard let self = self, !self.startResolved else { return }
            self.startResolved = true
            switch result {
            case .success(let url):
                self.startContinuation?.resume(returning: url)
            case .failure(let err):
                self.startContinuation?.resume(throwing: err)
            }
            self.startContinuation = nil
        }
    }

    private func fulfillCallback(with result: Result<CallbackParams, Error>) {
        queue.async { [weak self] in
            guard let self = self, !self.callbackResolved else { return }
            self.callbackResolved = true
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.listener.cancel()
            switch result {
            case .success(let params):
                self.callbackContinuation?.resume(returning: params)
            case .failure(let err):
                self.callbackContinuation?.resume(throwing: err)
            }
            self.callbackContinuation = nil
        }
    }

    // MARK: - Static HTML

    private static let successHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Clausage signed in</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0e0e10; color: #f5f5f7;
             display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
      .card { text-align: center; max-width: 420px; padding: 40px 32px; background: #1a1a1d; border-radius: 16px; }
      h1 { font-size: 22px; margin: 0 0 12px; }
      p { color: #aaa; line-height: 1.5; margin: 0; }
      .check { font-size: 56px; margin-bottom: 8px; }
    </style></head>
    <body>
      <div class="card">
        <div class="check">✓</div>
        <h1>You're signed in</h1>
        <p>You can close this tab and return to Clausage.</p>
      </div>
    </body></html>
    """

    private static let failureHTML = """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Clausage sign-in failed</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0e0e10; color: #f5f5f7;
             display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
      .card { text-align: center; max-width: 420px; padding: 40px 32px; background: #1a1a1d; border-radius: 16px; }
      h1 { font-size: 22px; margin: 0 0 12px; }
      p { color: #aaa; line-height: 1.5; margin: 0; }
      .x { font-size: 56px; margin-bottom: 8px; color: #ff6b6b; }
    </style></head>
    <body>
      <div class="card">
        <div class="x">×</div>
        <h1>Sign-in failed</h1>
        <p>Something went wrong. Open Clausage and try again.</p>
      </div>
    </body></html>
    """
}
