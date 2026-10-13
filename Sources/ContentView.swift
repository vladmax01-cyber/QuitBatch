import AppKit
import Carbon
import SwiftUI

private enum Palette {
    static let ink = Color.primary
    static let muted = Color.secondary

    static func accent(_ preferences: Preferences) -> Color {
        guard preferences.useCustomAccent else {
            return balanced(light: (0.20, 0.38, 0.62), dark: (0.52, 0.68, 0.84))
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(calibratedHue: preferences.customAccentHue,
                           saturation: dark ? 0.42 : 0.58,
                           brightness: dark ? 0.84 : 0.65, alpha: 1)
        })
    }

    private static func balanced(light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let components = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: components.0, green: components.1, blue: components.2, alpha: 1)
        })
    }

    static func color(_ name: String?, preferences: Preferences) -> Color {
        switch name {
        case "teal": balanced(light: (0.20, 0.46, 0.47), dark: (0.52, 0.75, 0.73))
        case "orange": balanced(light: (0.64, 0.39, 0.22), dark: (0.84, 0.68, 0.50))
        case "purple": balanced(light: (0.44, 0.35, 0.59), dark: (0.70, 0.61, 0.82))
        case "red": balanced(light: (0.62, 0.34, 0.37), dark: (0.84, 0.62, 0.64))
        default: accent(preferences)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let closePanel: () -> Void
    @State private var resizeStart: (mouse: NSPoint, size: CGSize, translation: CGSize)?
    @State private var resizeUsesScreenPointer = false
    @State private var pendingResize: CGSize?
    @State private var lastResizeUpdate = 0.0
    @State private var closeExpanded = true
    @State private var keepExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header
            navigation
            Divider().padding(.horizontal, 18)
            Group {
                switch model.section {
                case .openApps: OpenAppsView(model: model)
                case .profiles: ProfilesView(model: model, closeExpanded: $closeExpanded,
                                             keepExpanded: $keepExpanded)
                }
            }
            if let message = model.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Palette.accent(model.state.preferences))
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.message = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                }
                .font(.caption)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .padding([.horizontal, .bottom], 14)
            }
        }
        .frame(width: model.state.preferences.windowWidth, height: model.state.preferences.windowHeight)
        .background(AdjustableGlass(transparency: model.state.preferences.windowTransparency,
                                    enabled: model.state.preferences.useGlass))
        .preferredColorScheme(colorScheme)
        .tint(Palette.accent(model.state.preferences))
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .accessibilityLabel("Resize App Closer")
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let mouse = NSEvent.mouseLocation
                        if resizeStart == nil {
                            resizeStart = (
                                mouse,
                                CGSize(width: model.state.preferences.windowWidth,
                                       height: model.state.preferences.windowHeight),
                                gesture.translation
                            )
                        }
                        guard let resizeStart else { return }
                        let screenX = mouse.x - resizeStart.mouse.x
                        let screenY = resizeStart.mouse.y - mouse.y
                        if abs(screenX) + abs(screenY) > 1 { resizeUsesScreenPointer = true }
                        let offsetX = resizeUsesScreenPointer
                            ? resizeStart.translation.width + screenX : gesture.translation.width
                        let offsetY = resizeUsesScreenPointer
                            ? resizeStart.translation.height + screenY : gesture.translation.height
                        pendingResize = CGSize(width: resizeStart.size.width + offsetX,
                                               height: resizeStart.size.height + offsetY)
                        let now = Date.timeIntervalSinceReferenceDate
                        guard now - lastResizeUpdate >= 1.0 / 60.0, let pendingResize else { return }
                        lastResizeUpdate = now
                        model.resizePopover(width: pendingResize.width, height: pendingResize.height,
                                            persist: false)
                    }
                    .onEnded { _ in
                        if let pendingResize {
                            model.resizePopover(width: pendingResize.width, height: pendingResize.height,
                                                persist: true)
                        }
                        pendingResize = nil
                        resizeStart = nil
                        resizeUsesScreenPointer = false
                    })
        }
    }

    private var colorScheme: ColorScheme? {
        switch model.state.preferences.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: SymbolCatalog.menuBarImage(for: model.state.preferences.menuBarSymbol))
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Palette.accent(model.state.preferences))
                .frame(width: 30, height: 30)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("App Closer").font(.system(size: 18, weight: .semibold))
                Text("Manage running apps and saved profiles")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 17)) }
                .buttonStyle(.borderless)
                .help("Refresh running apps")
                .accessibilityLabel("Refresh running apps")
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 17)) }
                .buttonStyle(.borderless)
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
            Button(action: closePanel) { Image(systemName: "xmark").font(.system(size: 17)) }
                .buttonStyle(.borderless)
                .help("Close App Closer panel")
                .accessibilityLabel("Close App Closer panel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 15)
    }

    private var navigation: some View {
        HStack(spacing: 5) {
            ForEach(AppModel.Section.allCases) { section in
                Button {
                    model.section = section
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.symbol).font(.system(size: 16))
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: model.section == section ? .semibold : .medium))
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(model.section == section ? Color.primary.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

private struct OpenAppsView: View {
    @ObservedObject var model: AppModel
    @State private var showResults = false
    @State private var searchText = ""

    private var visibleApps: [RunningApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? model.apps : model.apps.filter { $0.name.localizedStandardContains(query) }
    }

    private var visibleSelectedCount: Int {
        visibleApps.filter { model.selectedPIDs.contains($0.id) && !$0.protected }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running applications").font(.headline)
                    Text("\(visibleApps.count) shown · \(model.selectedCount) selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All") { model.select(visibleApps) }
                    .disabled(visibleApps.allSatisfy(\.protected) || model.busy)
                Button("Deselect All") { model.deselect(visibleApps) }
                    .disabled(visibleSelectedCount == 0 || model.busy)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 9)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search running apps", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search running apps")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleApps) { app in
                        HStack(spacing: 11) {
                            Toggle(isOn: Binding(
                                get: { model.selectedPIDs.contains(app.id) },
                                set: { _ in model.toggle(app) }
                            )) {
                                HStack(spacing: 10) {
                                    Image(nsImage: app.icon)
                                        .resizable().interpolation(.high)
                                        .frame(width: 30, height: 30)
                                    Text(app.name)
                                        .lineLimit(1)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer(minLength: 8)
                                    if app.protected {
                                        Text("Protected").foregroundStyle(.secondary)
                                    } else if let result = model.resultByPID[app.id] {
                                        Text(result).foregroundStyle(result == "Needs manual close" ? .orange : .secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .toggleStyle(.checkbox)
                            .disabled(app.protected || model.busy)
                            if model.resultByPID[app.id] == "Needs manual close" {
                                Button { model.reveal(app) } label: { Image(systemName: "arrow.up.forward.app") }
                                    .buttonStyle(.borderless)
                                    .help("Bring \(app.name) forward to close it manually")
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(model.selectedPIDs.contains(app.id) ? 0.065 : 0.025),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 16)
            }
            .overlay {
                if model.apps.isEmpty {
                    ContentUnavailableView("No user apps found", systemImage: "app.dashed",
                                           description: Text("Open an application, then refresh this list."))
                } else if visibleApps.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }

            VStack(spacing: 9) {
                if model.busy { ProgressView(model.phase).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                if !model.lastResults.isEmpty {
                    DisclosureGroup("Last result", isExpanded: $showResults) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(model.lastResults.enumerated()), id: \.offset) { _, entry in
                                HStack {
                                    Text(entry.name).lineLimit(1)
                                    Spacer()
                                    Text(entry.status).foregroundStyle(entry.status == "Needs manual close" ? .orange : .secondary)
                                }
                            }
                        }
                        .font(.caption)
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
                Button { model.quitSelected() } label: {
                    Label(model.busy ? "Quitting Apps…" : "Quit Selected Apps", systemImage: "xmark.app.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(SoftActionStyle(color: Palette.accent(model.state.preferences)))
                .disabled(model.selectedCount == 0 || model.busy)
            }
            .padding(24)
        }
    }
}

private struct ProfilesView: View {
    @ObservedObject var model: AppModel
    @Binding var closeExpanded: Bool
    @Binding var keepExpanded: Bool
    @State private var deleteID: UUID?
    @State private var editingProfile = false
    @State private var showingProfileSymbols = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved profiles").font(.headline)
                Spacer()
                if model.state.profiles.count > 1 {
                    Button(model.state.preferences.showProfileStrip ? "Hide list" : "Show list") {
                        model.updatePreferences { $0.showProfileStrip.toggle() }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                Button {
                    model.createProfile()
                    editingProfile = true
                } label: { Label("New", systemImage: "plus") }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if model.state.profiles.count > 1 && model.state.preferences.showProfileStrip {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.state.profiles) { profile in
                            Button {
                                model.selectedProfileID = profile.id
                                editingProfile = false
                                showingProfileSymbols = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: profile.validSymbol)
                                        .font(.system(size: 17))
                                        .frame(width: 19)
                                        .foregroundStyle(Palette.color(profile.accent, preferences: model.state.preferences))
                                    Text(profile.name).lineLimit(1)
                                }
                                .font(.system(size: 13, weight: model.selectedProfileID == profile.id ? .semibold : .regular))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(model.selectedProfileID == profile.id ? Color.primary.opacity(0.11) : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 7)
            } else if model.state.profiles.count > 1 {
                Picker("Profile", selection: Binding(
                    get: { model.selectedProfileID },
                    set: { model.selectedProfileID = $0; editingProfile = false; showingProfileSymbols = false }
                )) {
                    ForEach(model.state.profiles) { profile in
                        Label(profile.name, systemImage: profile.validSymbol).tag(Optional(profile.id))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 7)
            }

            if let profile = model.selectedProfile {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        profileIdentity(profile)

                        profileAppSection("Close", entries: profile.close, id: profile.id, decision: .close)
                        profileAppSection("Keep Open", entries: profile.keep, id: profile.id, decision: .keep)

                        VStack(alignment: .leading, spacing: 8) {
                            profileToggle("Include newly detected apps", value: profile.includeNewApps, id: profile.id) { $0.includeNewApps = $1 }
                            Text("Closes running apps not listed above as Keep Open. Protected apps are never closed.")
                                .font(.caption2).foregroundStyle(.secondary)
                            profileToggle("Quit App Closer after running", value: profile.quitAfterRunning, id: profile.id) { $0.quitAfterRunning = $1 }
                            profileToggle("Offer workspace restoration after reopening", value: profile.restoreAfterReopening, id: profile.id) { $0.restoreAfterReopening = $1 }
                        }
                        .font(.caption)

                        Button { model.activateProfile(profile.id) } label: {
                            Label("Run \(profile.name.isEmpty ? "Profile" : profile.name)", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftActionStyle(color: Palette.color(profile.accent, preferences: model.state.preferences)))
                        .disabled(model.busy)
                        if !model.state.restorableApps.isEmpty {
                            Button("Restore Previous Workspace") { model.restoreWorkspace() }
                                .disabled(model.busy)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("No profile selected", systemImage: "square.on.square",
                                       description: Text("Create a profile to save an app list."))
            }
        }
        .alert("Delete profile?", isPresented: Binding(
            get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let id = deleteID { model.deleteProfile(id) }
                editingProfile = false
                deleteID = nil
            }
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: {
            Text("This saved profile will be removed.")
        }
    }

    private func profileIdentity(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: profile.validSymbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Palette.color(profile.accent, preferences: model.state.preferences))
                    .frame(width: 40, height: 40)
                    .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name.isEmpty ? "Untitled Profile" : profile.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("\(profile.close.count) Close  ·  \(profile.keep.count) Keep Open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(editingProfile ? "Done" : "Edit") { editingProfile.toggle() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(editingProfile ? "Finish editing profile" : "Edit profile")
                Menu {
                    Button {
                        model.duplicateProfile(profile.id)
                        editingProfile = true
                    } label: { Label("Duplicate Profile", systemImage: "plus.square.on.square") }
                    Button(role: .destructive) { deleteID = profile.id } label: {
                        Label("Delete Profile", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More profile actions")
                .accessibilityLabel("More profile actions")
            }
            if editingProfile {
                Divider()
                profileEditor(profile)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func profileEditor(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Name") {
                TextField("Profile name", text: Binding(
                    get: { model.selectedProfile?.name ?? "" },
                    set: { value in model.updateProfile(profile.id) { $0.name = value } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Text("Symbol").font(.subheadline.weight(.semibold))
                Spacer()
                Button { showingProfileSymbols.toggle() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: profile.validSymbol)
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.color(profile.accent, preferences: model.state.preferences))
                        Text("Choose")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose profile symbol")
                .popover(isPresented: $showingProfileSymbols, arrowEdge: .top) {
                    profileSymbolPicker(profile)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                TextField("Other SF Symbol name", text: Binding(
                    get: { model.selectedProfile?.symbol ?? "" },
                    set: { value in model.updateProfile(profile.id) { $0.symbol = value } }
                ))
                .textFieldStyle(.roundedBorder)
                Picker("Accent", selection: Binding(
                    get: { model.selectedProfile?.accent ?? "blue" },
                    set: { value in model.updateProfile(profile.id) { $0.accent = value == "blue" ? nil : value } }
                )) {
                    ForEach(["blue", "teal", "orange", "purple", "red"], id: \.self) { color in
                        Text(color == "blue" ? "App color" : color.capitalized).tag(color)
                    }
                }
                .frame(width: 125)
            }
            if NSImage(systemSymbolName: profile.symbol, accessibilityDescription: nil) == nil {
                Text("Symbol not found. App Closer will show its default icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func profileSymbolPicker(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile symbol").font(.headline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(SymbolCatalog.profileChoices) { choice in
                        Button {
                            model.updateProfile(profile.id) { $0.symbol = choice.id }
                            showingProfileSymbols = false
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: choice.id).font(.system(size: 21))
                                Text(choice.title).font(.caption2).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(profile.symbol == choice.id ? Palette.color(profile.accent, preferences: model.state.preferences) : Color.primary)
                            .background(profile.symbol == choice.id ? Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13) : Color.primary.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose \(choice.title) symbol")
                        .accessibilityAddTraits(profile.symbol == choice.id ? .isSelected : [])
                    }
                }
            }
            .frame(height: 235)
        }
        .padding(13)
        .frame(width: 310)
    }

    private func profileToggle(_ title: String, value: Bool, id: UUID,
                               change: @escaping (inout AppProfile, Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(
            get: { value },
            set: { newValue in model.updateProfile(id) { change(&$0, newValue) } }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private func profileAppSection(_ title: String, entries: [AppReference], id: UUID,
                                   decision: ProfileDecision) -> some View {
        let isExpanded = decision == .close ? $closeExpanded : $keepExpanded
        return LazyVStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { isExpanded.wrappedValue.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text("\(entries.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isExpanded.wrappedValue ? "Collapse" : "Expand") \(title)")
                .accessibilityValue("\(entries.count) apps")
                Spacer()
                Menu {
                    if !model.eligibleApps.isEmpty {
                        ForEach(model.eligibleApps) { app in
                            Button(app.name) { model.setApp(app.reference, decision: decision, profileID: id) }
                        }
                        Divider()
                    }
                    Button("Choose Application…") { model.addApplication(to: id, decision: decision) }
                } label: { Label("Add App", systemImage: "plus").font(.system(size: 14)) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            if isExpanded.wrappedValue {
                if decision == .close {
                    HStack(spacing: 14) {
                        Button("Select All") { model.selectAllAppsToClose(for: id) }
                            .disabled(model.eligibleApps.isEmpty || model.busy)
                            .help("Add running apps except Keep Open and protected apps")
                        Button("Deselect All") { model.clearAppsToClose(for: id) }
                            .disabled(entries.isEmpty || model.busy)
                        Spacer()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                if entries.isEmpty {
                    Text("No apps added").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Image(nsImage: ProfileIconCache.image(for: entry))
                                .resizable().frame(width: 24, height: 24)
                            Text(entry.name).font(.caption).lineLimit(1)
                            Spacer()
                            Button { model.updateProfile(id) { profile in
                                profile.close.removeAll { $0.id == entry.id }
                                profile.keep.removeAll { $0.id == entry.id }
                            }} label: { Image(systemName: "minus.circle").font(.system(size: 16)) }
                                .buttonStyle(.borderless)
                                .help("Remove \(entry.name) from profile")
                        }
                    }
                }
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }

}

@MainActor
private enum ProfileIconCache {
    static let images = NSCache<NSString, NSImage>()

    static func image(for entry: AppReference) -> NSImage {
        let key = (entry.path ?? entry.id) as NSString
        if let image = images.object(forKey: key) { return image }
        if let path = entry.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.id)?.path {
            let image = NSWorkspace.shared.icon(forFile: path)
            images.setObject(image, forKey: key)
            return image
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var recording = false
    @State private var showingSymbols = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { showingSymbols = true } label: {
                    Image(nsImage: SymbolCatalog.menuBarImage(for: model.state.preferences.menuBarSymbol))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Palette.accent(model.state.preferences))
                        .frame(width: 27, height: 27)
                        .frame(width: 48, height: 48)
                        .background(Palette.accent(model.state.preferences).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help("Change menu bar icon")
                .accessibilityLabel("Change menu bar icon")
                .popover(isPresented: $showingSymbols, arrowEdge: .bottom) { symbolPicker }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 20, weight: .semibold))
                    Text("Click the icon to choose your menu bar symbol")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    if let message = model.message {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                            Text(message).frame(maxWidth: .infinity, alignment: .leading)
                            Button { model.message = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                        }
                        .font(.caption)
                        .padding(12)
                        .background(Palette.accent(model.state.preferences).opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                    }

                    card("General", symbol: "switch.2") {
                        Toggle("Launch at login", isOn: Binding(
                            get: { model.state.preferences.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        Toggle("Confirm before quitting apps", isOn: Binding(
                            get: { model.state.preferences.confirmBeforeQuitting },
                            set: { value in model.updatePreferences { $0.confirmBeforeQuitting = value } }
                        ))
                        Button { NSApp.terminate(nil) } label: {
                            Label("Quit App Closer", systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                    }

                    card("Appearance", symbol: "circle.lefthalf.filled") {
                        HStack(spacing: 10) {
                            Text("Theme").font(.subheadline).frame(width: 88, alignment: .leading)
                            Picker("Theme", selection: Binding(
                                get: { model.state.preferences.appearance },
                                set: { value in model.updatePreferences { $0.appearance = value } }
                            )) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text("Accent color").font(.subheadline)
                                Spacer()
                                Circle()
                                    .fill(Palette.accent(model.state.preferences))
                                    .frame(width: 17, height: 17)
                                Button("Default") {
                                    model.updatePreferences { $0.useCustomAccent = false }
                                }
                                .controlSize(.small)
                                .disabled(!model.state.preferences.useCustomAccent)
                            }
                            AccentHueSlider(value: Binding(
                                get: { model.state.preferences.customAccentHue },
                                set: { model.setAccentHue($0, persist: false) }
                            ), onCommit: { model.save() })
                        }

                        Toggle("Use Liquid Glass", isOn: Binding(
                            get: { model.state.preferences.useGlass },
                            set: { value in model.updatePreferences { $0.useGlass = value } }
                        ))
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle("Show profile list", isOn: Binding(
                                get: { model.state.preferences.showProfileStrip },
                                set: { value in model.updatePreferences { $0.showProfileStrip = value } }
                            ))
                            Text("Shown when you have more than one profile.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Text("Transparency").font(.subheadline).frame(width: 88, alignment: .leading)
                            Slider(value: Binding(
                                get: { model.state.preferences.windowTransparency },
                                set: { value in model.updatePreferences { $0.windowTransparency = value } }
                            ), in: 0...1)
                            .accessibilityLabel("Panel transparency")
                            Text("\(Int((model.state.preferences.windowTransparency * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                        .disabled(!model.state.preferences.useGlass)
                    }

                    card("Keyboard shortcut", symbol: "keyboard") {
                        Text("None is set by default. Spotlight and existing shortcuts stay unchanged.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text(model.state.preferences.shortcut?.label ?? "None")
                                .font(.system(.body, design: .rounded))
                            Spacer()
                            if model.state.preferences.shortcut != nil {
                                Button("Clear") { model.updatePreferences { $0.shortcut = nil } }
                            }
                            Button(recording ? "Cancel" : "Record Shortcut") { recording.toggle() }
                        }
                        if recording {
                            ShortcutRecorder { shortcut in
                                model.updatePreferences { $0.shortcut = shortcut }
                                recording = false
                            }
                            .frame(height: 44)
                        }
                    }

                    card("Workspace", symbol: "square.stack.3d.up") {
                        HStack {
                            Text("\(model.state.restorableApps.count) app\(model.state.restorableApps.count == 1 ? "" : "s") saved for restoration")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore") { model.restoreWorkspace() }
                                .disabled(model.state.restorableApps.isEmpty || model.busy)
                        }
                    }

                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 430, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(colorScheme)
        .tint(Palette.accent(model.state.preferences))
    }

    private var colorScheme: ColorScheme? {
        switch model.state.preferences.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Menu bar icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                ForEach(SymbolCatalog.menuBarChoices) { choice in
                    Button {
                        model.updatePreferences { $0.menuBarSymbol = choice.id }
                        showingSymbols = false
                    } label: {
                        VStack(spacing: 5) {
                            Image(nsImage: SymbolCatalog.menuBarImage(for: choice.id))
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 26, height: 26)
                            Text(choice.title).font(.caption2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(model.state.preferences.menuBarSymbol == choice.id ? Palette.accent(model.state.preferences) : Color.primary)
                        .background(model.state.preferences.menuBarSymbol == choice.id ? Palette.accent(model.state.preferences).opacity(0.14) : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(choice.title) menu bar icon")
                }
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private func card<Content: View>(_ title: String, symbol: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent(model.state.preferences))
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct AccentHueSlider: View {
    @Binding var value: Double
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let thumbSize: CGFloat = 18
            let travel = max(0, geometry.size.width - thumbSize)

            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 7)
                .clipShape(Capsule())

                Circle()
                    .fill(Color(hue: value, saturation: 0.8, brightness: 0.95))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: travel * value)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    value = min(1, max(0, (gesture.location.x - thumbSize / 2) / max(travel, 1)))
                }
                .onEnded { _ in onCommit() })
        }
        .frame(height: 24)
        .focusable()
        .onKeyPress(.leftArrow) {
            value = max(0, value - 1.0 / 36)
            onCommit()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            value = min(1, value + 1.0 / 36)
            onCommit()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Accent color")
        .accessibilityValue("\(Int((value * 360).rounded())) degrees")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 1.0 / 36)
            case .decrement: value = max(0, value - 1.0 / 36)
            @unknown default: return
            }
            onCommit()
        }
    }
}

private struct AdjustableGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    let transparency: Double
    let enabled: Bool

    var body: some View {
        if !enabled || NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            Color(nsColor: .windowBackgroundColor)
        } else {
            ZStack {
                NativeGlassMaterial()
                Color(nsColor: .windowBackgroundColor)
                    .opacity(tintOpacity)
            }
        }
    }

    private var tintOpacity: Double {
        let amount = sqrt(min(1, max(0, transparency)))
        let minimum = colorScheme == .dark ? 0.22 : 0.21
        let maximum = colorScheme == .dark ? 0.62 : 0.72
        return maximum - ((maximum - minimum) * amount)
    }
}

private struct NativeGlassMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}

private struct SoftActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .background(color.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(RoundedRectangle(cornerRadius: 11))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.68),
                       value: configuration.isPressed)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    var onRecord: (Shortcut) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        return view
    }
    func updateNSView(_ view: RecorderView, context: Context) { view.onRecord = onRecord }

    final class RecorderView: NSView {
        var onRecord: ((Shortcut) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
        }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
            let text = "Press a key with ⌘, ⌥, or ⌃"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                             .foregroundColor: NSColor.secondaryLabelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                      withAttributes: attributes)
        }
        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            var label = ""
            if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
            if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
            if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
            guard modifiers & (UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)) != 0,
                  let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1 else {
                NSSound.beep()
                return
            }
            onRecord?(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + key))
        }
    }
}
