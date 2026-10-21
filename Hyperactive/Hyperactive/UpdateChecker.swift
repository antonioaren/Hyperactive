import AppKit
import Foundation
import Observation

/// A dotted numeric version such as `1.4.2`. A leading `v` and any pre-release
/// or build suffix (`-beta.1`, `+42`) are ignored. Missing components count as 0,
/// so `1.0` equals `1.0.0`.
struct AppVersion: Comparable, CustomStringConvertible {
    let components: [Int]

    init?(_ string: String) {
        var core = Substring(string.trimmingCharacters(in: .whitespacesAndNewlines))
        if core.first == "v" || core.first == "V" {
            core = core.dropFirst()
        }
        if let suffix = core.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            core = core[..<suffix]
        }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }

    static var installedString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var installed: AppVersion {
        AppVersion(installedString) ?? AppVersion("0")!
    }

    static var installedDescription: String {
        "Version \(installedString) (build \(installedBuild))"
    }
}

/// Checks GitHub Releases for a newer Hyperactive and installs it in place.
///
/// The release workflow publishes `Hyperactive-X.Y.Z-macOS.zip`. Installing
/// downloads that zip, checks the bundle id, version and code signature, swaps
/// the app bundle on disk (asking for an administrator password only if the
/// current location is not writable), then quits and relaunches the new copy.
@Observable
final class UpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: AppVersion
        let pageURL: URL
        let downloadURL: URL?
    }

    static let releasesPageURL = URL(string: "https://github.com/antonioaren/Hyperactive/releases/latest")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/antonioaren/Hyperactive/releases/latest")!
    private static let appAssetSuffix = "-macOS.zip"
    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let launchCheckDelay: TimeInterval = 5

    private(set) var state: State = .idle
    private(set) var availableRelease: Release?
    private(set) var lastChecked: Date?

    @ObservationIgnored private var timer: Timer?

    init() {
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchCheckDelay) { [weak self] in
            self?.checkForUpdates()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Background checks stay quiet on failure; a check the user asked for reports the error.
    func checkForUpdates(userInitiated: Bool = false) {
        guard state != .checking, state != .installing else { return }
        state = .checking

        var request = URLRequest(url: Self.latestReleaseAPI)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hyperactive/\(AppVersion.installedString)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Self.parseLatestRelease(data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastChecked = Date()
                switch result {
                case .success(let release):
                    if let release, release.version > AppVersion.installed {
                        self.availableRelease = release
                        self.state = .updateAvailable
                    } else {
                        self.availableRelease = nil
                        self.state = .upToDate
                    }
                case .failure(let error):
                    if userInitiated {
                        self.state = .failed("Could not check for updates: \(error.localizedDescription)")
                    } else {
                        self.state = self.availableRelease == nil ? .idle : .updateAvailable
                    }
                }
            }
        }.resume()
    }

    /// `beforeRelaunch` runs after the new app is on disk, right before this process quits.
    func installUpdate(beforeRelaunch: @escaping () -> Void) {
        guard state != .installing, let release = availableRelease else { return }
        guard let downloadURL = release.downloadURL else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        if let problem = Self.installLocationProblem() {
            state = .failed("Update failed: \(problem.localizedDescription)")
            return
        }

        state = .installing

        URLSession.shared.downloadTask(with: downloadURL) { [weak self] location, response, error in
            // `location` is deleted when this handler returns, so move it out first.
            let downloaded = Result<(workDirectory: URL, archive: URL), Error> {
                if let error { throw error }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError.badResponse
                }
                let workDirectory = try Self.makeWorkDirectory()
                let archive = workDirectory.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: location, to: archive)
                return (workDirectory, archive)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let staged = downloaded.flatMap { download in
                    Result<(workDirectory: URL, app: URL), Error> {
                        do {
                            let app = try Self.stageUpdate(
                                archive: download.archive,
                                in: download.workDirectory,
                                expecting: release.version
                            )
                            return (download.workDirectory, app)
                        } catch {
                            try? FileManager.default.removeItem(at: download.workDirectory)
                            throw error
                        }
                    }
                }

                DispatchQueue.main.async {
                    guard let self else { return }
                    switch staged {
                    case .success(let update):
                        self.replaceAndRelaunch(
                            with: update.app,
                            workDirectory: update.workDirectory,
                            expecting: release.version,
                            beforeRelaunch: beforeRelaunch
                        )
                    case .failure(let error):
                        self.state = .failed("Update failed: \(error.localizedDescription)")
                    }
                }
            }
        }.resume()
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(availableRelease?.pageURL ?? Self.releasesPageURL)
    }

    // MARK: - Checking

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }

        let tagName: String
        let htmlUrl: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    /// `.success(nil)` means there is no usable published release.
    private static func parseLatestRelease(data: Data?, response: URLResponse?, error: Error?) -> Result<Release?, Error> {
        if let error {
            return .failure(error)
        }
        guard let http = response as? HTTPURLResponse, let data else {
            return .failure(UpdateError.badResponse)
        }
        if http.statusCode == 404 {
            return .success(nil)
        }
        guard http.statusCode == 200 else {
            return .failure(UpdateError.httpStatus(http.statusCode))
        }
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let payload = try decoder.decode(GitHubRelease.self, from: data)
            guard !payload.draft, !payload.prerelease, let version = AppVersion(payload.tagName) else {
                return .success(nil)
            }
            let asset = payload.assets.first { $0.name.hasSuffix(appAssetSuffix) }
            return .success(Release(version: version, pageURL: payload.htmlUrl, downloadURL: asset?.browserDownloadUrl))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Installing

    private enum UpdateError: LocalizedError {
        case badResponse
        case httpStatus(Int)
        case invalidBundle
        case versionMismatch
        case translocated
        case readOnlyLocation
        case commandFailed(String)
        case administratorDenied
        case replaceFailed

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "Unexpected response from GitHub."
            case .httpStatus(let code):
                return "GitHub returned HTTP \(code)."
            case .invalidBundle:
                return "The download is not a valid Hyperactive app."
            case .versionMismatch:
                return "The download has an unexpected version."
            case .translocated:
                return "Move Hyperactive to the Applications folder, open it from there, and try again."
            case .readOnlyLocation:
                return "Hyperactive is running from a read-only location. Move it to the Applications folder."
            case .commandFailed(let tool):
                return "\(tool) failed while preparing the update."
            case .administratorDenied:
                return "Administrator permission is required to replace the app."
            case .replaceFailed:
                return "Could not replace the installed app."
            }
        }
    }

    /// Gatekeeper runs quarantined apps from a randomized read-only path; replacing it would not stick.
    private static func installLocationProblem() -> UpdateError? {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.path.contains("/AppTranslocation/") {
            return .translocated
        }
        if let values = try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]), values.volumeIsReadOnly == true {
            return .readOnlyLocation
        }
        return nil
    }

    private static func makeWorkDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HyperactiveUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Unzips the download and returns the new app bundle once it passes validation.
    private static func stageUpdate(archive: URL, in workDirectory: URL, expecting version: AppVersion) throws -> URL {
        let extracted = workDirectory.appendingPathComponent("extracted", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])

        let contents = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.invalidBundle
        }

        let info = bundleInfo(at: app)
        guard let identifier = info?["CFBundleIdentifier"] as? String, identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.invalidBundle
        }
        guard let versionString = info?["CFBundleShortVersionString"] as? String,
              AppVersion(versionString) == version else {
            throw UpdateError.versionMismatch
        }

        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    private func replaceAndRelaunch(
        with newApp: URL,
        workDirectory: URL,
        expecting version: AppVersion,
        beforeRelaunch: () -> Void
    ) {
        let destination = Bundle.main.bundleURL
        let backup = workDirectory.appendingPathComponent("Previous.app", isDirectory: true)

        do {
            if Self.canWriteInPlace(destination) {
                try Self.swapInPlace(destination: destination, newApp: newApp, backup: backup)
            } else {
                try Self.swapWithAdministrator(destination: destination, newApp: newApp, backup: backup)
            }

            guard let installed = Self.bundleInfo(at: destination)?["CFBundleShortVersionString"] as? String,
                  AppVersion(installed) == version else {
                throw UpdateError.replaceFailed
            }

            try Self.scheduleRelaunch(of: destination, cleaningUp: workDirectory)
        } catch {
            // The backup lives in the work directory; only discard it if the app is still in place.
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: workDirectory)
            }
            state = .failed("Update failed: \(error.localizedDescription)")
            return
        }

        beforeRelaunch()
        NSApplication.shared.terminate(nil)
    }

    private static func canWriteInPlace(_ destination: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isWritableFile(atPath: destination.deletingLastPathComponent().path)
            && fileManager.isWritableFile(atPath: destination.path)
    }

    private static func swapInPlace(destination: URL, newApp: URL, backup: URL) throws {
        let fileManager = FileManager.default
        try fileManager.moveItem(at: destination, to: backup)
        do {
            try fileManager.moveItem(at: newApp, to: destination)
        } catch {
            try? fileManager.moveItem(at: backup, to: destination)
            throw error
        }
    }

    private static func swapWithAdministrator(destination: URL, newApp: URL, backup: URL) throws {
        let dest = shellQuoted(destination.path)
        let new = shellQuoted(newApp.path)
        let old = shellQuoted(backup.path)
        let command = "/bin/mv -f \(dest) \(old) && { /bin/mv -f \(new) \(dest) || { /bin/mv -f \(old) \(dest); exit 1; }; }"
        let source = "do shell script \"\(appleScriptEscaped(command))\" with administrator privileges"

        guard let script = NSAppleScript(source: source) else {
            throw UpdateError.replaceFailed
        }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if error != nil {
            throw UpdateError.administratorDenied
        }
    }

    /// Waits for this process to exit, opens the new app, then removes the work directory.
    private static func scheduleRelaunch(of app: URL, cleaningUp workDirectory: URL) throws {
        let script = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open "$2"
        /bin/rm -rf "$3"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "hyperactive-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            app.path,
            workDirectory.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func bundleInfo(at app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed((executable as NSString).lastPathComponent)
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
