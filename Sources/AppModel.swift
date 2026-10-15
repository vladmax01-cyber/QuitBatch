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
    @Published private(set) var usageByPID: [pid_t: ResourceUsage] = [:]
    @Published var resultByPID: [pid_t: String] = [:]
    @Published var lastResults: [(pid: pid_t, name: String, status: String)] = []
    @Published private(set) var pendingForceQuitCount = 0
    @Published var message: String?
    @Published var section: PanelSection = .openApps
    @Published var customizingSections = false

    private let store: StateStore
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var resourceTimer: Timer?
    private var resourceSnapshots: [pid_t: ProcessResourceSnapshot] = [:]
    private var pendingForceQuitTargets: [RunningApp] = []
    private var pendingForceQuitProfile: AppProfile?
    var onShortcutChanged: ((Shortcut?) -> Void)?
    var onSizeChanged: ((CGSize) -> Void)?
    var onMenuBarSymbolChanged: ((String) -> Void)?
    var onKeepPanelWithSettingsChanged: ((Bool) -> Void)?

    init(store: StateStore = StateStore()) {
        self.store = store
        do { state = try store.load() }
        catch {
            state = .initial()
            message = "Could not read saved profiles: \(error.localizedDescription)"
        }
        section = visibleSections.first ?? .openApps
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
        resourceTimer?.invalidate()
    }

    var eligibleApps: [RunningApp] { apps.filter { !$0.protected } }
    var selectedCount: Int { eligibleApps.filter { selectedPIDs.contains($0.id) }.count }
    var selectedProfile: AppProfile? { state.profiles.first { $0.id == selectedProfileID } }
    var visibleSections: [PanelSection] {
        state.preferences.sectionOrder.filter { !state.preferences.hiddenSections.contains($0) }
    }

    func setSectionVisible(_ item: PanelSection, visible: Bool) {
        guard visible || visibleSections.count > 1 else { return }
        updatePreferences {
            if visible { $0.hiddenSections.remove(item) }
            else { $0.hiddenSections.insert(item) }
        }
        if !visible && section == item { section = visibleSections.first ?? .openApps }
    }

    func moveSection(_ item: PanelSection, to destination: Int) {
        updatePreferences { preferences in
            preferences.sectionOrder.removeAll { $0 == item }
            preferences.sectionOrder.insert(item, at: min(max(destination, 0), preferences.sectionOrder.count))
        }
    }

    func selectAppSortMode(_ mode: AppSortMode) {
        updatePreferences { $0.appSortMode = mode }
    }

    func moveAppSortMode(_ mode: AppSortMode, to destination: Int) {
        updatePreferences { preferences in
            preferences.appSortOrder.removeAll { $0 == mode }
            preferences.appSortOrder.insert(mode, at: min(max(destination, 0), preferences.appSortOrder.count))
        }
    }

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
        if !pendingForceQuitTargets.isEmpty {
            let alreadyClosed = pendingForceQuitTargets.filter { $0.application.isTerminated }
            for target in alreadyClosed { resultByPID[target.id] = "Closed" }
            pendingForceQuitTargets.removeAll { $0.application.isTerminated }
            pendingForceQuitCount = pendingForceQuitTargets.count
            if !alreadyClosed.isEmpty {
                lastResults = lastResults.map { ($0.pid, $0.name, resultByPID[$0.pid] ?? $0.status) }
            }
        }
        if resourceTimer != nil { refreshResources() }
    }

    func setPanelVisible(_ visible: Bool) {
        if visible {
            guard resourceTimer == nil else { return }
            refresh()
            refreshResources()
            resourceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshResources()
                }
            }
        } else {
            resourceTimer?.invalidate()
            resourceTimer = nil
            resourceSnapshots.removeAll()
        }
    }

    private func refreshResources() {
        let time = ProcessInfo.processInfo.systemUptime
        var nextSnapshots: [pid_t: ProcessResourceSnapshot] = [:]
        var nextUsage: [pid_t: ResourceUsage] = [:]
        for app in apps {
            guard let snapshot = ResourceSampler.read(pid: app.id, at: time) else { continue }
            nextUsage[app.id] = ResourceSampler.usage(current: snapshot, previous: resourceSnapshots[app.id])
            nextSnapshots[app.id] = snapshot
        }
        resourceSnapshots = nextSnapshots
        if nextUsage != usageByPID { usageByPID = nextUsage }
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
        updateProfile(profileID) {
            $0.close.removeAll()
            $0.includeNewApps = false
        }
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
        let automaticForceQuit = state.preferences.forceQuitUnresponsiveApps
        resultByPID = [:]
        lastResults = []
        message = nil
        pendingForceQuitTargets = []
        pendingForceQuitProfile = nil
        pendingForceQuitCount = 0
        let ordered = targets.sorted { a, b in
            let aHammer = a.application.bundleIdentifier?.localizedCaseInsensitiveContains("hammerspoon") == true
            let bHammer = b.application.bundleIdentifier?.localizedCaseInsensitiveContains("hammerspoon") == true
            return aHammer == bHammer ? a.name.localizedStandardCompare(b.name) == .orderedAscending : !aHammer
        }
        phase = "Asking \(ordered.count) apps to quit…"
        var active: [RunningApp] = []
        for target in ordered {
            let app = target.application
            if app.isTerminated { resultByPID[target.id] = "Already closed"; continue }
            guard !target.protected else { resultByPID[target.id] = "Protected"; continue }
            resultByPID[target.id] = "Quitting…"
            _ = app.terminate()
            active.append(target)
        }
        phase = "Waiting for apps to close…"
        await waitForExit(of: active, seconds: 4)
        let remaining = active.filter { !$0.application.isTerminated }
        var forceAttempted: Set<pid_t> = []
        if automaticForceQuit && !remaining.isEmpty {
            phase = "Force quitting \(remaining.count) apps…"
            for target in remaining where !target.protected && !target.application.isTerminated {
                forceAttempted.insert(target.id)
                _ = target.application.forceTerminate()
            }
            await waitForExit(of: remaining, seconds: 3)
        }
        let closed = ordered.filter { $0.application.isTerminated }
        let stillRunning = ordered.filter { !$0.application.isTerminated && !$0.protected }
        for target in ordered where resultByPID[target.id] != "Protected" {
            if target.application.isTerminated {
                resultByPID[target.id] = forceAttempted.contains(target.id) ? "Force quit" : "Closed"
            } else {
                resultByPID[target.id] = "Still running"
            }
        }
        saveRestorable(closed, for: profile)
        refresh()
        selectedPIDs.subtract(closed.map(\.id))
        pendingForceQuitTargets = stillRunning
        pendingForceQuitProfile = profile
        pendingForceQuitCount = stillRunning.count
        phase = ""
        busy = false
        lastResults = ordered.map { ($0.id, $0.name, resultByPID[$0.id] ?? "Unknown") }
        message = stillRunning.isEmpty ? "Closed \(closed.count) app\(closed.count == 1 ? "" : "s")." :
            "Closed \(closed.count). \(stillRunning.count) still running."
        if stillRunning.isEmpty && profile?.quitAfterRunning == true { NSApp.terminate(nil) }
    }

    func forceQuitRemaining() {
        guard !busy else { return }
        let targets = pendingForceQuitTargets.filter { !$0.application.isTerminated && !$0.protected }
        guard !targets.isEmpty else {
            pendingForceQuitTargets = []
            pendingForceQuitCount = 0
            message = "Those apps have already closed."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Force quit \(targets.count) app\(targets.count == 1 ? "" : "s")?"
        alert.informativeText = "Only apps from the last QuitBatch run that are still open will be forced to close. Unsaved changes may be lost."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Quit")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await forceQuit(targets, profile: pendingForceQuitProfile) }
    }

    private func forceQuit(_ targets: [RunningApp], profile: AppProfile?) async {
        busy = true
        phase = "Force quitting \(targets.count) apps…"
        for target in targets where !target.application.isTerminated && !target.protected {
            _ = target.application.forceTerminate()
        }
        await waitForExit(of: targets, seconds: 3)
        let closed = targets.filter { $0.application.isTerminated }
        let stillRunning = targets.filter { !$0.application.isTerminated && !$0.protected }
        for target in targets {
            resultByPID[target.id] = target.application.isTerminated ? "Force quit" : "Still running"
        }
        saveRestorable(closed, for: profile)
        refresh()
        selectedPIDs.subtract(closed.map(\.id))
        pendingForceQuitTargets = stillRunning
        pendingForceQuitCount = stillRunning.count
        lastResults = lastResults.map { ($0.pid, $0.name, resultByPID[$0.pid] ?? $0.status) }
        phase = ""
        busy = false
        message = stillRunning.isEmpty ? "Force quit \(closed.count) app\(closed.count == 1 ? "" : "s")." :
            "Force quit \(closed.count). \(stillRunning.count) could not be closed."
        if stillRunning.isEmpty && profile?.quitAfterRunning == true { NSApp.terminate(nil) }
    }

    private func waitForExit(of targets: [RunningApp], seconds: TimeInterval) async {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while targets.contains(where: { !$0.application.isTerminated }) && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func saveRestorable(_ closed: [RunningApp], for profile: AppProfile?) {
        guard profile?.restoreAfterReopening == true else { return }
        for target in closed where target.reference.path != nil &&
            !state.restorableApps.contains(where: { $0.id == target.reference.id }) {
            state.restorableApps.append(target.reference)
        }
        save()
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
        let previous = state.preferences
        var updated = previous
        change(&updated)
        guard updated != previous else { return }
        state.preferences = updated
        save()
        if previous.appearance != state.preferences.appearance { applyAppearance() }
        if previous.shortcut != state.preferences.shortcut { onShortcutChanged?(state.preferences.shortcut) }
        if previous.menuBarSymbol != state.preferences.menuBarSymbol {
            onMenuBarSymbolChanged?(state.preferences.menuBarSymbol)
        }
        if previous.keepPanelOpenWithSettings != state.preferences.keepPanelOpenWithSettings {
            onKeepPanelWithSettingsChanged?(state.preferences.keepPanelOpenWithSettings)
        }
    }

    func setAccentHue(_ hue: Double, persist: Bool) {
        state.preferences.customAccentHue = min(1, max(0, hue))
        state.preferences.useCustomAccent = true
        if persist { save() }
    }

    func setAccentDarkness(_ darkness: Double, persist: Bool) {
        state.preferences.accentDarkness = min(1, max(0, darkness))
        if persist { save() }
    }

    func setWindowTransparency(_ transparency: Double, persist: Bool) {
        state.preferences.windowTransparency = min(1, max(0, transparency))
        if persist { save() }
    }

    func resizePopover(width: Double, height: Double, persist: Bool) {
        let newWidth = min(720, max(380, width.rounded()))
        let newHeight = min(900, max(460, height.rounded()))
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
