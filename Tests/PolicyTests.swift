import AppKit
import Foundation

@main
struct PolicyTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let original = SavedState.initial()
        precondition(original.profiles.count == 1)
        precondition(original.profiles[0].name == "Exam Mode")
        precondition(original.preferences.shortcut == nil)
        let earlierSettings = Data(#"{"launchAtLogin":false,"confirmBeforeQuitting":false,"appearance":"system"}"#.utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: earlierSettings)
        precondition(migrated.useGlass && migrated.windowTransparency == 0.08)
        precondition(!migrated.forceQuitUnresponsiveApps)
        precondition(migrated.openAppsIconSize == .small && migrated.profilesIconSize == .small)
        let iconSettings = try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"openAppsIconSize":"medium","profilesIconSize":"large"}"#.utf8))
        precondition(iconSettings.openAppsIconSize == .medium && iconSettings.profilesIconSize == .large)
        let invalidIconSettings = try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"openAppsIconSize":"unknown"}"#.utf8))
        precondition(invalidIconSettings.openAppsIconSize == .small)
        let forceQuitSettings = try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"forceQuitUnresponsiveApps":true}"#.utf8))
        precondition(forceQuitSettings.forceQuitUnresponsiveApps)
        let halfSecondOfTicks = UInt64((1_000_000_000 / ResourceSampler.nanosecondsPerTick).rounded())
        let earlierSample = ProcessResourceSnapshot(cpuTicks: 1_000_000_000,
                                                    memoryBytes: 100, sampledAt: 10, startTicks: 42)
        let laterSample = ProcessResourceSnapshot(cpuTicks: 1_000_000_000 + halfSecondOfTicks,
                                                  memoryBytes: 200, sampledAt: 12, startTicks: 42)
        let measured = ResourceSampler.usage(current: laterSample, previous: earlierSample)
        precondition(abs((measured.cpuPercent ?? -1) - 50) < 0.001 && measured.memoryBytes == 200)
        precondition(ResourceSampler.usage(current: laterSample, previous: nil).cpuPercent == nil)
        let reusedPID = ProcessResourceSnapshot(cpuTicks: laterSample.cpuTicks + 1000,
                                                memoryBytes: 300, sampledAt: 13, startTicks: 43)
        precondition(ResourceSampler.usage(current: reusedPID, previous: laterSample).cpuPercent == nil)
        precondition(ResourceSampler.read(pid: getpid(), at: 12)?.memoryBytes ?? 0 > 0)
        precondition(migrated.showProfileStrip)
        precondition(!migrated.useCustomAccent && migrated.customAccentHue == 0.59)
        precondition(migrated.accentDarkness == 0)
        let customAccent = try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"useCustomAccent":true,"customAccentHue":1.5,"accentDarkness":1.8}"#.utf8))
        precondition(customAccent.useCustomAccent && customAccent.customAccentHue == 1 &&
                     customAccent.accentDarkness == 1)
        let blue = NSColor(deviceRed: 0, green: 0.478, blue: 1, alpha: 1)
        let lightBackground = NSColor(calibratedWhite: 1, alpha: 1)
        let darkBackground = NSColor(calibratedWhite: 0.118, alpha: 1)
        let deepBlue = AccentTone.adjusted(blue, darkness: 1, darkAppearance: false)
        precondition(AccentTone.contrast(deepBlue, against: lightBackground) >
                     AccentTone.contrast(blue, against: lightBackground))
        let graphite = AccentTone.adjusted(NSColor(calibratedWhite: 0.6, alpha: 1),
                                           darkness: 1, darkAppearance: false)
        precondition(abs(graphite.redComponent - graphite.blueComponent) < 0.02)
        for hue in stride(from: 0.0, through: 0.8, by: 0.2) {
            let base = NSColor(calibratedHue: hue, saturation: 0.8, brightness: 1, alpha: 1)
            for (dark, background) in [(false, lightBackground), (true, darkBackground)] {
                let starting = AccentTone.contrast(base, against: background)
                let ending = dark ? min(starting, 3) : max(starting, 9)
                for amount in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let tinted = AccentTone.adjusted(base, darkness: amount, darkAppearance: dark)
                    let actual = AccentTone.contrast(tinted, against: background)
                    let expected = starting + (ending - starting) * amount
                    precondition(abs(actual - expected) < 0.03)
                    let foreground = AccentTone.readableForeground(tinted, darkAppearance: dark)
                    precondition(AccentTone.contrast(foreground, against: background) >= 4.49)
                    precondition(AccentTone.contrast(AccentTone.textOnFill(tinted),
                                                      against: tinted) >= 3.99)
                }
            }
        }
        precondition(migrated.windowWidth == 400 && migrated.windowHeight == 500)
        precondition(migrated.menuBarSymbol == "appcloser")
        precondition(Set(SymbolCatalog.profileChoices.map(\.id)).count == SymbolCatalog.profileChoices.count)
        precondition(Set(SymbolCatalog.menuBarChoices.map(\.id)).count == SymbolCatalog.menuBarChoices.count)
        precondition(SymbolCatalog.profileChoices.allSatisfy { NSImage(systemSymbolName: $0.id, accessibilityDescription: nil) != nil })
        precondition(SymbolCatalog.menuBarChoices.filter { $0.id != "appcloser" }
            .allSatisfy { NSImage(systemSymbolName: $0.id, accessibilityDescription: nil) != nil })
        precondition(SymbolCatalog.menuBarImage(for: "appcloser").isTemplate)

        var profile = original.profiles[0]
        let notes = AppReference(id: "com.apple.Notes", name: "Notes")
        let safari = AppReference(id: "com.apple.Safari", name: "Safari")
        precondition(AppPolicy.decision(for: notes, protected: false, profile: profile) == .keep)
        profile.close.append(notes)
        precondition(AppPolicy.decision(for: notes, protected: false, profile: profile) == .close)
        profile.includeNewApps = true
        precondition(AppPolicy.decision(for: safari, protected: false, profile: profile) == .keep)
        precondition(AppPolicy.decision(for: notes, protected: true, profile: profile) == .protected)
        precondition(AppPolicy.protectedBundleIDs.contains("com.respondus.lockdownbrowser"))
        precondition(AppPolicy.protectedBundleIDs.contains("com.vladikmartinez.appcloser"))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppCloserTests-\(UUID())")
        let store = StateStore(url: directory.appendingPathComponent("state.json"))
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = original
        state.profiles.append(profile)
        state.preferences.shortcut = Shortcut(keyCode: 0, modifiers: 0, label: "Test")
        state.preferences.menuBarSymbol = "xmark.app"
        state.preferences.showProfileStrip = false
        state.restorableApps = [notes]
        try store.save(state)
        let loaded = try store.load()
        precondition(loaded.profiles == state.profiles)
        precondition(loaded.preferences == state.preferences)
        precondition(loaded.restorableApps == state.restorableApps)

        let model = AppModel(store: store)
        model.setAccentHue(0.74, persist: true)
        let savedAccent = try store.load().preferences
        precondition(savedAccent.useCustomAccent && savedAccent.customAccentHue == 0.74)
        model.setAccentDarkness(0.2, persist: true)
        let savedDarkness = try store.load().preferences.accentDarkness
        precondition(savedDarkness == 0.2)
        model.setAccentDarkness(1, persist: true)
        let maximumDarkness = try store.load().preferences.accentDarkness
        precondition(maximumDarkness == 1)
        model.updatePreferences { $0.openAppsIconSize = .large; $0.profilesIconSize = .medium }
        let savedIconSizes = try store.load().preferences
        precondition(savedIconSizes.openAppsIconSize == .large && savedIconSizes.profilesIconSize == .medium)
        model.setWindowTransparency(0.65, persist: true)
        let savedTransparency = try store.load().preferences.windowTransparency
        precondition(savedTransparency == 0.65)
        model.createProfile()
        guard let created = model.selectedProfileID else { fatalError("Profile was not selected") }
        model.updateProfile(created) { $0.name = "Test Profile" }
        model.duplicateProfile(created)
        guard let duplicate = model.selectedProfileID else { fatalError("Duplicate was not selected") }
        precondition(model.state.profiles.first(where: { $0.id == duplicate })?.name == "Test Profile Copy")
        model.deleteProfile(created)
        model.deleteProfile(duplicate)
        precondition(model.state.profiles.count == 2)
        let examID = model.state.profiles[0].id
        if let appToKeep = model.eligibleApps.first {
            model.setApp(appToKeep.reference, decision: .keep, profileID: examID)
        }
        model.selectAllAppsToClose(for: examID)
        guard let selectedProfile = model.state.profiles.first(where: { $0.id == examID }) else {
            fatalError("Exam profile was not found")
        }
        let keptIDs = Set(selectedProfile.keep.map(\.id))
        let closedIDs = Set(selectedProfile.close.map(\.id))
        precondition(closedIDs.count == selectedProfile.close.count)
        precondition(closedIDs.isDisjoint(with: keptIDs))
        precondition(model.eligibleApps.allSatisfy { keptIDs.contains($0.reference.id) || closedIDs.contains($0.reference.id) })
        model.updateProfile(examID) { $0.includeNewApps = true }
        model.clearAppsToClose(for: examID)
        precondition(model.state.profiles.first(where: { $0.id == examID })?.close.isEmpty == true)
        precondition(model.state.profiles.first(where: { $0.id == examID })?.includeNewApps == false)
        model.selectAll()
        precondition(model.apps.filter(\.protected).allSatisfy { !model.selectedPIDs.contains($0.id) })
        model.deselectAll()
        precondition(model.selectedCount == 0)
        var resizeEvents = 0
        model.onSizeChanged = { _ in resizeEvents += 1 }
        model.resizePopover(width: 999, height: 100, persist: true)
        precondition(model.state.preferences.windowWidth == 720)
        precondition(model.state.preferences.windowHeight == 460)
        model.resizePopover(width: 719.6, height: 460.2, persist: true)
        precondition(resizeEvents == 1)
        model.resizePopover(width: 600, height: 600, persist: false)
        let beforeResizeSave = try store.load()
        precondition(beforeResizeSave.preferences.windowWidth == 720)
        model.resizePopover(width: 600, height: 600, persist: true)
        let afterResizeSave = try store.load()
        precondition(afterResizeSave.preferences.windowWidth == 600)
        model.resizePopover(width: 1, height: 1, persist: true)
        precondition(model.state.preferences.windowWidth == 380)
        precondition(model.state.preferences.windowHeight == 460)
        let finalState = try store.load()
        precondition(finalState.profiles.count == 2)
        print("Policy, profile editing, selection, and persistence tests passed")
    }
}
