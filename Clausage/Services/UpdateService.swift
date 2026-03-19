import Foundation
import AppKit

@Observable
final class UpdateService {
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    static let repoOwner = "mauribadnights"
    static let repoName = "clausage"

    var updateAvailable: String?
    var isChecking = false
    var isUpdating = false
    var updateError: String?

    private var checkTimer: Timer?

    init() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            let s = self
            Task { @MainActor in s?.checkForUpdate() }
        }
        Task { @MainActor in
            self.checkForUpdate()
        }
    }

    @MainActor
    func checkForUpdate() {
        isChecking = true
        updateError = nil

        Task.detached(priority: .utility) {
            let result = Self.fetchLatestRelease()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isChecking = false
                switch result {
                case .success(let release):
                    if Self.isNewer(release.tagName, than: Self.currentVersion) {
                        self.updateAvailable = release.tagName
                    } else {
                        self.updateAvailable = nil
                    }
                case .failure(let error):
                    self.updateError = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    func performUpdate() {
        guard let version = updateAvailable else { return }
        isUpdating = true
        updateError = nil

        Task.detached(priority: .userInitiated) {
            let result = Self.downloadAndInstall(version: version)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUpdating = false
                switch result {
                case .success:
                    Self.relaunch()
                case .failure(let error):
                    self.updateError = "Update failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Private

    private struct Release {
        let tagName: String
        let assetURL: String?
    }

    private static func fetchLatestRelease() -> Result<Release, Error> {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return .failure(NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?

        URLSession.shared.dataTask(with: request) { data, _, error in
            responseData = data
            responseError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = responseError {
            return .failure(error)
        }

        guard let data = responseData,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return .failure(NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse release"]))
        }

        var assetURL: String?
        if let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                if let name = asset["name"] as? String,
                   name.hasSuffix(".app.zip"),
                   let downloadURL = asset["browser_download_url"] as? String {
                    assetURL = downloadURL
                    break
                }
            }
        }

        return .success(Release(tagName: tagName, assetURL: assetURL))
    }

    private static func downloadAndInstall(version: String) -> Result<Void, Error> {
        let releaseResult = fetchLatestRelease()
        guard case .success(let release) = releaseResult,
              let assetURL = release.assetURL,
              let url = URL(string: assetURL) else {
            return .failure(NSError(domain: "UpdateService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No download available"]))
        }

        let semaphore = DispatchSemaphore(value: 0)
        var downloadedData: Data?
        var downloadError: Error?

        URLSession.shared.dataTask(with: url) { data, _, error in
            downloadedData = data
            downloadError = error
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let error = downloadError {
            return .failure(error)
        }

        guard let data = downloadedData else {
            return .failure(NSError(domain: "UpdateService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClausageUpdate-\(UUID().uuidString)")
        let zipPath = tempDir.appendingPathComponent("Clausage.app.zip")

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try data.write(to: zipPath)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipPath.path, "-d", tempDir.path]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                return .failure(NSError(domain: "UpdateService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip"]))
            }

            let newAppPath = tempDir.appendingPathComponent("Clausage.app")
            guard FileManager.default.fileExists(atPath: newAppPath.path) else {
                return .failure(NSError(domain: "UpdateService", code: 6, userInfo: [NSLocalizedDescriptionKey: "App not found in archive"]))
            }

            guard let currentAppPath = Bundle.main.bundleURL.path.removingPercentEncoding else {
                return .failure(NSError(domain: "UpdateService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Cannot find current app"]))
            }

            let currentURL = URL(fileURLWithPath: currentAppPath)
            let backupURL = currentURL.deletingLastPathComponent().appendingPathComponent("Clausage.app.bak")

            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.moveItem(at: currentURL, to: backupURL)
            try FileManager.default.moveItem(at: newAppPath, to: currentURL)

            // Remove quarantine flag from downloaded app
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-rd", "com.apple.quarantine", currentURL.path]
            xattr.standardOutput = FileHandle.nullDevice
            xattr.standardError = FileHandle.nullDevice
            try? xattr.run()
            xattr.waitUntilExit()

            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.removeItem(at: tempDir)

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func relaunch() {
        guard let appPath = Bundle.main.bundleURL.path.removingPercentEncoding else { return }
        // Use a longer delay and explicit relaunch to ensure the old process is fully gone
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", """
            sleep 2
            open "\(appPath)"
            # If open fails (e.g. quarantine), try again after clearing it
            if [ $? -ne 0 ]; then
                xattr -rd com.apple.quarantine "\(appPath)" 2>/dev/null
                sleep 1
                open "\(appPath)"
            fi
            """]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteClean = remote.hasPrefix("v") ? String(remote.dropFirst()) : remote
        let localClean = local.hasPrefix("v") ? String(local.dropFirst()) : local

        let remoteParts = remoteClean.split(separator: ".").compactMap { Int($0) }
        let localParts = localClean.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}
