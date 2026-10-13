import AppKit
import Combine
import ServiceManagement

struct RunningApp: Identifiable {
    let application: NSRunningApplication
    let reference: AppReference
    let icon: NSImage
    init(application: NSRunningApplication) {
        self.application = application
        reference = AppReference(application: application)
        icon = application.icon ?? NSWorkspace.shared.icon(forFile: application.bundleURL?.path ?? "")
    }
    var id: pid_t { application.processIdentifier }
    var name: String { reference.name }
    var protected: Bool { AppPolicy.isProtected(application) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var apps: [RunningApp] = []
    @Published var selectedPIDs: Set<pid_t> = []
    @Published private(set) var state: SavedState
    @Published var selectedProfileID: UUID?
    @Published var busy = false
    @Published var phase = ""
    @Published var resultByPID: [pid_t: String] = [:]
    @Published var lastResults: [(name: String, status: String)] = []
    @Published var message: String?
    @Published var section: Section = .openApps

    enum Section: String, CaseIterable, Identifiable {
        case openApps = "Open Apps"
        case profiles = "Profiles"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .openApps: "square.stack.3d.up"
            case .profiles: "square.on.square"
            }
        }
    }

    private let store: StateStore
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    var onShortcutChanged: ((Shortcut?) -> Void)?
    var onSizeChanged: ((CGSize) -> Void)?
    var onMenuBarSymbolChanged: ((String) -> Void)?

    init(store: StateStore = StateStore()) {
        self.store = store
        do { state = try store.load() }
        catch {
            state = .initial()
            message = "Could not read saved profiles: \(error.localizedDescription)"
        }
        selectedProfileID = state.profiles.first?.id
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        state.preferences.launchAtLogin = SMAppService.mainApp.status == .enabled
        applyAppearance()
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        timer?.invalidate()
    }

    var eligibleApps: [RunningApp] { apps.filter { !$0.protected } }
    var selectedCount: Int { eligibleApps.filter { selectedPIDs.contains($0.id) }.count }
    var selectedProfile: AppProfile? { state.profiles.first { $0.id == selectedProfileID } }

    func refresh() {
        let running = NSWorkspace.shared.runningApplications
            .filter { app in
                guard !app.isTerminated, app.bundleURL != nil else { return false }
                if app.activationPolicy == .regular { return true }
                if app.activationPolicy == .accessory {
                    if app.bundleIdentifier?.lowercased().hasPrefix("com.apple.") == true { return false }
                    return app.bundleURL?.pathExtension.lowercased() == "app"
                }
                return false
            }
        let currentPIDs = Set(running.map(\.processIdentifier))
        if currentPIDs == Set(apps.map(\.id)) { return }
        apps = running.map(RunningApp.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let active = Set(apps.map(\.id))
        selectedPIDs.formIntersection(active)
    }

    func selectAll() { selectedPIDs = Set(eligibleApps.map(\.id)) }
    func select(_ visibleApps: [RunningApp]) {
        selectedPIDs.formUnion(visibleApps.filter { !$0.protected }.map(\.id))
    }
    func deselectAll() { selectedPIDs.removeAll() }
    func deselect(_ visibleApps: [RunningApp]) {
        selectedPIDs.subtract(visibleApps.map(\.id))
    }
    func toggle(_ app: RunningApp) {
        guard !app.protected else { return }
        if selectedPIDs.contains(app.id) { selectedPIDs.remove(app.id) }
        else { selectedPIDs.insert(app.id) }
    }

    func save() {
        do { try store.save(state) }
        catch { message = "Could not save settings: \(error.localizedDescription)" }
    }

    func createProfile() {
        let profile = AppProfile(id: UUID(), name: "New Profile", symbol: "square.stack.3d.up", accent: nil,
                                 close: [], keep: [], includeNewApps: false,
                                 quitAfterRunning: false, restoreAfterReopening: false)
        state.profiles.append(profile)
        selectedProfileID = profile.id
        save()
    }

    func duplicateProfile(_ id: UUID) {
        guard var profile = state.profiles.first(where: { $0.id == id }) else { return }
        profile.id = UUID()
        profile.name += " Copy"
        state.profiles.append(profile)
        selectedProfileID = profile.id
        save()
    }

    func deleteProfile(_ id: UUID) {
        state.profiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = state.profiles.first?.id }
        save()
    }

    func updateProfile(_ id: UUID, _ change: (inout AppProfile) -> Void) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        change(&state.profiles[index])
        save()
    }

    func setApp(_ reference: AppReference, decision: ProfileDecision, profileID: UUID) {
        updateProfile(profileID) { profile in
            profile.close.removeAll { $0.id == reference.id }
            profile.keep.removeAll { $0.id == reference.id }
            switch decision {
            case .close: profile.close.append(reference)
            case .keep: profile.keep.append(reference)
            case .protected: break
            }
        }
    }

    func selectAllAppsToClose(for profileID: UUID) {
        let running = eligibleApps.map(\.reference)
        updateProfile(profileID) { profile in
            let keptIDs = Set(profile.keep.map(\.id))
            var closedIDs = Set(profile.close.map(\.id))
            for app in running where !keptIDs.contains(app.id) && closedIDs.insert(app.id).inserted {
                profile.close.append(app)
            }
        }
    }

    func clearAppsToClose(for profileID: UUID) {
        updateProfile(profileID) { $0.close.removeAll() }
    }

    func addApplication(to profileID: UUID, decision: ProfileDecision) {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let bundle = Bundle(url: url)
            let id = bundle?.bundleIdentifier ?? url.path
            if AppPolicy.protectedBundleIDs.contains(id.lowercased()) { continue }
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            setApp(AppReference(id: id, name: name, path: url.path), decision: decision, profileID: profileID)
        }
    }

    func quitSelected() {
        let targets = apps.filter { selectedPIDs.contains($0.id) && !$0.protected }
        beginQuit(targets, profile: nil)
    }

    func activateProfile(_ id: UUID) {
        guard let profile = state.profiles.first(where: { $0.id == id }) else { return }
        refresh()
        let targets = apps.filter {
            AppPolicy.decision(for: $0.reference, protected: $0.protected, profile: profile) == .close
        }
        beginQuit(targets, profile: profile)
    }

    private func beginQuit(_ targets: [RunningApp], profile: AppProfile?) {
        guard !busy else { return }
        guard !targets.isEmpty else {
            message = profile == nil ? "Select at least one app to quit." : "No running apps match this profile."
            return
        }
        if state.preferences.confirmBeforeQuitting {
            let alert = NSAlert()
            alert.messageText = "Quit \(targets.count) application\(targets.count == 1 ? "" : "s")?"
            alert.informativeText = "Apps with unsaved work may ask you to confirm before closing."
            alert.addButton(withTitle: "Quit Apps")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        Task { await quit(targets, profile: profile) }
    }

    private func quit(_ targets: [RunningApp], profile: AppProfile?) async {
        busy = true
        resultByPID = [:]
        lastResults = []
        message = nil
        var closed: [AppReference] = []
        var failed = 0
        let ordered = targets.sorted { a, b in
            let aHammer = a.application.bundleIdentifier?.localizedCaseInsensitiveContains("hammerspoon") == true
            let bHammer = b.application.bundleIdentifier?.localizedCaseInsensitiveContains("hammerspoon") == true
            return !aHammer && bHammer
        }
        for (index, target) in ordered.enumerated() {
            let app = target.application
            if app.isTerminated { resultByPID[target.id] = "Already closed"; continue }
            phase = "Quitting \(index + 1) of \(ordered.count): \(target.name)"
            resultByPID[target.id] = "Quitting…"
            if !app.terminate() {
                resultByPID[target.id] = "Needs manual close"
                failed += 1
                continue
            }
            for _ in 0..<24 {
                if app.isTerminated { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if app.isTerminated {
                resultByPID[target.id] = "Closed"
                closed.append(target.reference)
            } else {
                resultByPID[target.id] = "Needs manual close"
                failed += 1
            }
        }
        if profile?.restoreAfterReopening == true {
            for app in closed where app.path != nil && !state.restorableApps.contains(where: { $0.id == app.id }) {
                state.restorableApps.append(app)
            }
            save()
        }
        refresh()
        selectedPIDs.subtract(closed.compactMap { ref in targets.first(where: { $0.reference.id == ref.id })?.id })
        phase = ""
        busy = false
        lastResults = ordered.map { ($0.name, resultByPID[$0.id] ?? "Unknown") }
        message = failed == 0 ? "Closed \(closed.count) selected app\(closed.count == 1 ? "" : "s")." :
            "Closed \(closed.count). \(failed) app\(failed == 1 ? "" : "s") need manual attention."
        if failed == 0 && profile?.quitAfterRunning == true { NSApp.terminate(nil) }
    }

    func reveal(_ app: RunningApp) {
        app.application.activate(options: [])
    }

    func restoreWorkspace() {
        guard !busy else { return }
        let entries = state.restorableApps
        guard !entries.isEmpty else { message = "There are no apps to restore."; return }
        busy = true
        phase = "Restoring workspace…"
        Task {
            var remaining: [AppReference] = []
            var restored = 0
            for entry in entries {
                guard let path = entry.path else { remaining.append(entry); continue }
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else { remaining.append(entry); continue }
                if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == entry.id }) {
                    restored += 1
                    continue
                }
                let success = await withCheckedContinuation { continuation in
                    NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                        continuation.resume(returning: error == nil)
                    }
                }
                if success { restored += 1 } else { remaining.append(entry) }
            }
            state.restorableApps = remaining
            save()
            busy = false
            phase = ""
            message = remaining.isEmpty ? "Restored \(restored) app\(restored == 1 ? "" : "s")." :
                "Restored \(restored). \(remaining.count) could not be reopened."
            refresh()
        }
    }

    func updatePreferences(_ change: (inout Preferences) -> Void) {
        let oldShortcut = state.preferences.shortcut
        let oldMenuBarSymbol = state.preferences.menuBarSymbol
        change(&state.preferences)
        save()
        applyAppearance()
        if oldShortcut != state.preferences.shortcut { onShortcutChanged?(state.preferences.shortcut) }
        if oldMenuBarSymbol != state.preferences.menuBarSymbol {
            onMenuBarSymbolChanged?(state.preferences.menuBarSymbol)
        }
    }

    func setAccentHue(_ hue: Double, persist: Bool) {
        state.preferences.customAccentHue = min(1, max(0, hue))
        state.preferences.useCustomAccent = true
        if persist { save() }
    }

    func resizePopover(width: Double, height: Double, persist: Bool) {
        let newWidth = min(720, max(420, width.rounded()))
        let newHeight = min(900, max(520, height.rounded()))
        guard newWidth != state.preferences.windowWidth || newHeight != state.preferences.windowHeight else {
            if persist { save() }
            return
        }
        state.preferences.windowWidth = newWidth
        state.preferences.windowHeight = newHeight
        onSizeChanged?(CGSize(width: state.preferences.windowWidth, height: state.preferences.windowHeight))
        if persist { save() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updatePreferences { $0.launchAtLogin = enabled }
        } catch {
            message = "Could not change login setting: \(error.localizedDescription)"
        }
    }

    func applyAppearance() {
        switch state.preferences.appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
