import AppKit
import CryptoKit
import Foundation

@MainActor
final class Updater: ObservableObject {
    static let repo = "maxamly/wizbar"

    enum State: Equatable {
        case idle, checking, upToDate, installing
        case available(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var release: Release?
    private var timer: Timer?

    private struct Release {
        let version: String
        let zip: URL
        let checksum: URL
    }

    struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    init() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            await check(manual: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { await self?.check(manual: false) }
        }
    }

    func check(manual: Bool) async {
        if state == .installing { return }
        if manual { state = .checking }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]]
            else { throw UpdateError("Unexpected response from GitHub.") }

            func asset(_ name: String) -> URL? {
                assets.first { $0["name"] as? String == name }
                    .flatMap { $0["browser_download_url"] as? String }
                    .flatMap(URL.init(string:))
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.compare(version, currentVersion) == .orderedDescending,
               let zip = asset("WizBar.zip"), let checksum = asset("WizBar.zip.sha256") {
                release = Release(version: version, zip: zip, checksum: checksum)
                state = .available(version)
            } else {
                release = nil
                state = manual ? .upToDate : .idle
                if manual {
                    try? await Task.sleep(for: .seconds(4))
                    if state == .upToDate { state = .idle }
                }
            }
        } catch {
            if manual { state = .failed("Couldn't check for updates.") }
        }
    }

    func install() async {
        guard let release else { return await check(manual: true) }
        state = .installing
        do {
            let app = try await Self.download(release)
            try Self.replace(Bundle.main.bundleURL, with: app)
            Self.relaunch(Bundle.main.bundleURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func download(_ release: Release) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WizBarUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let (downloaded, _) = try await URLSession.shared.download(from: release.zip)
        let zip = dir.appendingPathComponent("WizBar.zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        let (sumData, _) = try await URLSession.shared.data(from: release.checksum)
        let expected = String(decoding: sumData, as: UTF8.self).split(whereSeparator: \.isWhitespace).first ?? ""
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard expected.lowercased() == actual else { throw UpdateError("The download didn't match its checksum.") }

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        let app = dir.appendingPathComponent("WizBar.app")
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              compare(version, release.version) == .orderedSame
        else { throw UpdateError("The download isn't a valid WizBar \(release.version).") }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }

    nonisolated private static func replace(_ current: URL, with new: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: new)
        } catch {
            // replaceItemAt can't cross volumes; fall back to remove + copy.
            try FileManager.default.removeItem(at: current)
            try FileManager.default.copyItem(at: new, to: current)
        }
    }

    private static func relaunch(_ app: URL) {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? shell.run()
        NSApp.terminate(nil)
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed while installing the update.")
        }
    }

    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
