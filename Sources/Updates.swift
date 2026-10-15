import Combine
import Foundation

struct ReleaseVersion {
    static func components(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        return numbers.count == parts.count ? numbers : nil
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        guard let candidate = components(candidate), let installed = components(installed) else { return false }
        for index in 0..<max(candidate.count, installed.count) {
            let newer = index < candidate.count ? candidate[index] : 0
            let current = index < installed.count ? installed[index] : 0
            if newer != current { return newer > current }
        }
        return false
    }
}

struct AvailableRelease: Equatable {
    let tag: String
    let url: URL
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published private(set) var availableRelease: AvailableRelease?
    private var nextCheck = Date.distantPast
    private let endpoint = URL(string: "https://api.github.com/repos/vladmax01-cyber/QuitBatch/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/vladmax01-cyber/QuitBatch/releases/latest")!
    private let dismissedKey = "QuitBatchDismissedRelease"

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
    }

    static func availableRelease(from data: Data, installedVersion: String,
                                 dismissedTag: String?) -> AvailableRelease? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              !release.draft, !release.prerelease,
              ReleaseVersion.isNewer(release.tag_name, than: installedVersion),
              release.tag_name != dismissedTag else { return nil }
        return AvailableRelease(tag: release.tag_name, url: releasesPage)
    }

    func checkIfNeeded(now: Date = Date()) {
        guard now >= nextCheck else { return }
        nextCheck = now.addingTimeInterval(15 * 60)
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("QuitBatch", forHTTPHeaderField: "User-Agent")
        Task {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let status = (response as? HTTPURLResponse)?.statusCode else { return }
            if status == 404 {
                nextCheck = Date().addingTimeInterval(12 * 60 * 60)
                availableRelease = nil
                return
            }
            guard status == 200,
                  let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                if status == 200 { nextCheck = Date().addingTimeInterval(12 * 60 * 60) }
                return
            }
            nextCheck = Date().addingTimeInterval(12 * 60 * 60)
            availableRelease = Self.availableRelease(
                from: data, installedVersion: installed,
                dismissedTag: UserDefaults.standard.string(forKey: dismissedKey))
        }
    }

    func dismiss() {
        guard let availableRelease else { return }
        UserDefaults.standard.set(availableRelease.tag, forKey: dismissedKey)
        self.availableRelease = nil
    }
}
