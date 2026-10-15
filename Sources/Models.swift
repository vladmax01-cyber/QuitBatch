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

enum IconSizeOption: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var artwork: CGFloat {
        switch self { case .small: 20; case .medium: 26; case .large: 32 }
    }
    var badge: CGFloat { artwork + 12 }
}

enum ChromeIconMetrics {
    static let brand: CGFloat = 26
    static let action: CGFloat = 17
    static let section: CGFloat = 16
}

enum PanelSection: String, Codable, CaseIterable, Identifiable {
    case openApps, profiles, drives

    var id: String { rawValue }
    var title: String {
        switch self {
        case .openApps: "Apps"
        case .profiles: "Profiles"
        case .drives: "Drives"
        }
    }
    var symbol: String {
        switch self {
        case .openApps: "square.stack.3d.up"
        case .profiles: "square.on.square"
        case .drives: "externaldrive"
        }
    }
}

enum AppSortMode: String, Codable, CaseIterable, Identifiable {
    case name, cpu, memory

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "Name"
        case .cpu: "CPU"
        case .memory: "Memory"
        }
    }
}

enum ReorderMath {
    static func destination(startIndex: Int, translation: CGFloat, pitch: CGFloat, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return startIndex }
        let steps = Int((translation / pitch).rounded())
        return min(count - 1, max(0, startIndex + steps))
    }

    static func clampedTranslation(_ translation: CGFloat, from index: Int, pitch: CGFloat, count: Int) -> CGFloat {
        guard count > 0, pitch > 0 else { return 0 }
        return min(CGFloat(count - 1 - index) * pitch, max(-CGFloat(index) * pitch, translation))
    }

    static func shift(index: Int, from source: Int, to destination: Int, pitch: CGFloat) -> CGFloat {
        if source < destination && index > source && index <= destination { return -pitch }
        if source > destination && index >= destination && index < source { return pitch }
        return 0
    }
}

struct Preferences: Codable, Equatable {
    static let defaultAccentDarkness = 0.0

    var launchAtLogin = false
    var confirmBeforeQuitting = false
    var forceQuitUnresponsiveApps = false
    var appearance = "system"
    var menuBarSymbol = "appcloser"
    var shortcut: Shortcut? = nil
    var useGlass = true
    var showProfileStrip = true
    var keepPanelOpenWithSettings = true
    var openAppsIconSize: IconSizeOption = .small
    var profilesIconSize: IconSizeOption = .small
    var useCustomAccent = false
    var customAccentHue = 0.59
    var accentDarkness = Preferences.defaultAccentDarkness
    var windowTransparency = 0.08
    var windowWidth = 400.0
    var windowHeight = 500.0
    var sectionOrder: [PanelSection] = PanelSection.allCases
    var hiddenSections: Set<PanelSection> = []
    var appSortMode: AppSortMode = .name
    var appSortOrder: [AppSortMode] = AppSortMode.allCases

    init() {}

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, confirmBeforeQuitting, forceQuitUnresponsiveApps, appearance, menuBarSymbol, shortcut, useGlass, showProfileStrip,
             keepPanelOpenWithSettings,
             openAppsIconSize, profilesIconSize,
             useCustomAccent, customAccentHue, accentDarkness, windowTransparency,
             windowWidth, windowHeight, sectionOrder, hiddenSections, appSortMode, appSortOrder
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        confirmBeforeQuitting = try values.decodeIfPresent(Bool.self, forKey: .confirmBeforeQuitting) ?? false
        forceQuitUnresponsiveApps = try values.decodeIfPresent(Bool.self, forKey: .forceQuitUnresponsiveApps) ?? false
        appearance = try values.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
        let savedSymbol = try values.decodeIfPresent(String.self, forKey: .menuBarSymbol) ?? "appcloser"
        menuBarSymbol = SymbolCatalog.menuBarChoices.contains(where: { $0.id == savedSymbol })
            ? savedSymbol : "appcloser"
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        useGlass = try values.decodeIfPresent(Bool.self, forKey: .useGlass) ?? true
        showProfileStrip = try values.decodeIfPresent(Bool.self, forKey: .showProfileStrip) ?? true
        keepPanelOpenWithSettings = try values.decodeIfPresent(Bool.self, forKey: .keepPanelOpenWithSettings) ?? true
        openAppsIconSize = (try? values.decode(IconSizeOption.self, forKey: .openAppsIconSize)) ?? .small
        profilesIconSize = (try? values.decode(IconSizeOption.self, forKey: .profilesIconSize)) ?? .small
        useCustomAccent = try values.decodeIfPresent(Bool.self, forKey: .useCustomAccent) ?? false
        customAccentHue = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .customAccentHue) ?? 0.59))
        accentDarkness = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .accentDarkness) ?? Preferences.defaultAccentDarkness))
        windowTransparency = min(1, max(0, try values.decodeIfPresent(Double.self, forKey: .windowTransparency) ?? 0.08))
        windowWidth = min(720, max(380, try values.decodeIfPresent(Double.self, forKey: .windowWidth) ?? 400))
        windowHeight = min(900, max(460, try values.decodeIfPresent(Double.self, forKey: .windowHeight) ?? 500))
        let savedOrder = (try? values.decode([PanelSection].self, forKey: .sectionOrder)) ?? []
        var seen: Set<PanelSection> = []
        sectionOrder = (savedOrder + PanelSection.allCases).filter { seen.insert($0).inserted }
        hiddenSections = (try? values.decode(Set<PanelSection>.self, forKey: .hiddenSections)) ?? []
        if hiddenSections.count == PanelSection.allCases.count { hiddenSections.remove(.openApps) }
        appSortMode = (try? values.decode(AppSortMode.self, forKey: .appSortMode)) ?? .name
        let savedSortOrder = (try? values.decode([AppSortMode].self, forKey: .appSortOrder)) ?? []
        var seenSortModes: Set<AppSortMode> = []
        appSortOrder = (savedSortOrder + AppSortMode.allCases).filter { seenSortModes.insert($0).inserted }
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
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(SavedState.self, from: data)
        } catch {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("state-unreadable-\(UUID().uuidString).json")
            try data.write(to: backup, options: .atomic)
            throw error
        }
    }

    func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }
}
