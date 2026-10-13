import AppKit
import Foundation

struct AppReference: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var path: String?

    init(application: NSRunningApplication) {
        id = application.bundleIdentifier ?? application.bundleURL?.path ?? "pid:\(application.processIdentifier)"
        name = application.localizedName ?? application.bundleURL?.deletingPathExtension().lastPathComponent ?? id
        path = application.bundleURL?.path
    }

    init(id: String, name: String, path: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
    }
}

struct AppProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var symbol: String
    var accent: String?
    var close: [AppReference]
    var keep: [AppReference]
    var includeNewApps: Bool
    var quitAfterRunning: Bool
    var restoreAfterReopening: Bool

    var validSymbol: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil
            ? "square.stack.3d.up" : symbol
    }

    static func example() -> AppProfile {
        AppProfile(
            id: UUID(), name: "Exam Mode", symbol: "graduationcap", accent: "blue",
            close: [],
            keep: [AppReference(id: "com.apple.Safari", name: "Safari"),
                   AppReference(id: "com.google.Chrome", name: "Google Chrome")],
            includeNewApps: false, quitAfterRunning: false, restoreAfterReopening: false
        )
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
}

struct Preferences: Codable, Equatable {
    static let defaultAccentDarkness = 0.0

    var launchAtLogin = false
    var confirmBeforeQuitting = false
    var appearance = "system"
    var menuBarSymbol = "appcloser"
    var shortcut: Shortcut? = nil
    var useGlass = true
    var showProfileStrip = true
    var useCustomAccent = false
    var customAccentHue = 0.59
    var accentDarkness = Preferences.defaultAccentDarkness
    var windowTransparency = 0.08
    var windowWidth = 440.0
    var windowHeight = 626.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, confirmBeforeQuitting, appearance, menuBarSymbol, shortcut, useGlass, showProfileStrip,
             useCustomAccent, customAccentHue, accentDarkness, windowTransparency,
             windowWidth, windowHeight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        confirmBeforeQuitting = try values.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuitting) ?? false
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        let savedSymbol = try values.decodeIfPresent(String.self, forKey: .menuBarSymbol) ?? "appcloser"
        menuBarSymbol = SymbolCatalog.menuBarChoices.contains(where: { $0.id == savedSymbol })
            ? savedSymbol : "appcloser"
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        useGlass = try values.decodeIfPresent(Bool.self, forKey: .useGlass) ?? true
        showProfileStrip = try values.decodeIfPresent(Bool.self, forKey: .showProfileStrip) ?? true
        useCustomAccent = try values.decodeIfPresent(Bool.self, forKey: .useCustomAccent) ?? false
        customAccentHue = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .customAccentHue) ?? 0.59))
        accentDarkness = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .accentDarkness) ?? Preferences.defaultAccentDarkness))
        windowTransparency = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .windowTransparency) ?? 0.08))
        windowWidth = min(720, max(420, try values.decodeIfPresent(Double.self, forKey: .windowWidth) ?? 440))
        windowHeight = min(900, max(520, try values.decodeIfPresent(Double.self, forKey: .windowHeight) ?? 626))
    }
}

struct SavedState: Codable {
    var profiles: [AppProfile]
    var preferences: Preferences
    var restorableApps: [AppReference]

    static func initial() -> SavedState {
        SavedState(profiles: [.example()], preferences: Preferences(), restorableApps: [])
    }
}

enum ProfileDecision: Equatable {
    case protected
    case close
    case keep
}

enum AppPolicy {
    static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.apple.systemuiserver", "com.apple.controlcenter",
        "com.apple.notificationcenterui", "com.apple.windowmanager",
        "com.respondus.lockdownbrowser", "com.vladikmartinez.appcloser",
        "com.vladikmartinez.appcloser.preview"
    ]

    static func isProtected(_ application: NSRunningApplication) -> Bool {
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        guard let identifier = application.bundleIdentifier else { return false }
        return protectedBundleIDs.contains(identifier.lowercased())
    }

    static func decision(for app: AppReference, protected: Bool, profile: AppProfile) -> ProfileDecision {
        if protected { return .protected }
        if profile.keep.contains(where: { $0.id == app.id }) { return .keep }
        if profile.close.contains(where: { $0.id == app.id }) { return .close }
        return profile.includeNewApps ? .close : .keep
    }
}

final class StateStore {
    let url: URL

    init(url overrideURL: URL? = nil) {
        if let overrideURL { url = overrideURL; return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = support.appendingPathComponent("App Closer", isDirectory: true).appendingPathComponent("state.json")
    }

    func load() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .initial() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }

    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }
}
