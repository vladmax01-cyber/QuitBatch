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
        precondition(migrated.showProfileStrip)
        precondition(!migrated.useCustomAccent && migrated.customAccentHue == 0.59)
        precondition(migrated.accentDarkness == 0.08)
        let customAccent = try JSONDecoder().decode(Preferences.self,
            from: Data(#"{"useCustomAccent":true,"customAccentHue":1.5,"accentDarkness":0.8}"#.utf8))
        precondition(customAccent.useCustomAccent && customAccent.customAccentHue == 1 &&
                     customAccent.accentDarkness == 0.35)
        precondition(migrated.windowWidth == 440 && migrated.windowHeight == 626)
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
        model.clearAppsToClose(for: examID)
        precondition(model.state.profiles.first(where: { $0.id == examID })?.close.isEmpty == true)
        model.selectAll()
        precondition(model.apps.filter(\.protected).allSatisfy { !model.selectedPIDs.contains($0.id) })
        model.deselectAll()
        precondition(model.selectedCount == 0)
        var resizeEvents = 0
        model.onSizeChanged = { _ in resizeEvents += 1 }
        model.resizePopover(width: 999, height: 100, persist: true)
        precondition(model.state.preferences.windowWidth == 720)
        precondition(model.state.preferences.windowHeight == 520)
        model.resizePopover(width: 719.6, height: 520.2, persist: true)
        precondition(resizeEvents == 1)
        model.resizePopover(width: 600, height: 600, persist: false)
        let beforeResizeSave = try store.load()
        precondition(beforeResizeSave.preferences.windowWidth == 720)
        model.resizePopover(width: 600, height: 600, persist: true)
        let afterResizeSave = try store.load()
        precondition(afterResizeSave.preferences.windowWidth == 600)
        let finalState = try store.load()
        precondition(finalState.profiles.count == 2)
        print("Policy, profile editing, selection, and persistence tests passed")
    }
}
