import AppKit
import Carbon
import SwiftUI

private enum Palette {
    static let ink = Color.primary
    static let muted = Color.secondary

    static func accent(_ preferences: Preferences) -> Color {
        return Color(nsColor: NSColor(name: nil) { appearance in
            resolvedAccent(preferences, appearance: appearance)
        })
    }

    static func accentForeground(_ preferences: Preferences) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let color = resolvedAccent(preferences, appearance: appearance)
            return preferences.accentDarkness == 0 ? color :
                AccentTone.readableForeground(color, darkAppearance: dark)
        })
    }

    static func textOnAccent(_ preferences: Preferences) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            AccentTone.textOnFill(resolvedAccent(preferences, appearance: appearance))
        })
    }

    private static func resolvedAccent(_ preferences: Preferences, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var base = NSColor(calibratedHue: preferences.customAccentHue,
                           saturation: dark ? 0.75 : 0.8,
                           brightness: dark ? 1 : 0.95, alpha: 1)
        if !preferences.useCustomAccent {
            appearance.performAsCurrentDrawingAppearance {
                base = NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? NSColor.controlAccentColor
            }
        }
        return AccentTone.adjusted(base, darkness: preferences.accentDarkness, darkAppearance: dark)
    }

    private static func profileColors(_ name: String?) ->
        (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat))? {
        switch name {
        case "teal": ((0.20, 0.46, 0.47), (0.52, 0.75, 0.73))
        case "orange": ((0.64, 0.39, 0.22), (0.84, 0.68, 0.50))
        case "purple": ((0.44, 0.35, 0.59), (0.70, 0.61, 0.82))
        case "red": ((0.62, 0.34, 0.37), (0.84, 0.62, 0.64))
        default: nil
        }
    }

    private static func balanced(light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat),
                                 preferences: Preferences, readable: Bool = false,
                                 textOnFill: Bool = false) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let components = isDark ? dark : light
            let base = NSColor(srgbRed: components.0, green: components.1, blue: components.2, alpha: 1)
            let color = AccentTone.adjusted(base, darkness: preferences.accentDarkness,
                                            darkAppearance: isDark)
            if textOnFill { return AccentTone.textOnFill(color) }
            return readable && preferences.accentDarkness > 0 ?
                AccentTone.readableForeground(color, darkAppearance: isDark) : color
        })
    }

    static func color(_ name: String?, preferences: Preferences) -> Color {
        guard let colors = profileColors(name) else { return accent(preferences) }
        return balanced(light: colors.light, dark: colors.dark, preferences: preferences)
    }

    static func foregroundColor(_ name: String?, preferences: Preferences) -> Color {
        guard let colors = profileColors(name) else { return accentForeground(preferences) }
        return balanced(light: colors.light, dark: colors.dark, preferences: preferences,
                        readable: true)
    }

    static func textOnColor(_ name: String?, preferences: Preferences) -> Color {
        guard let colors = profileColors(name) else { return textOnAccent(preferences) }
        return balanced(light: colors.light, dark: colors.dark, preferences: preferences,
                        textOnFill: true)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var updates = UpdateChecker.shared
    @StateObject private var drives = DriveManager()
    let openSettings: () -> Void
    let closePanel: () -> Void
    @State private var resizeStart: (mouse: NSPoint, size: CGSize, translation: CGSize)?
    @State private var resizeUsesScreenPointer = false
    @State private var pendingResize: CGSize?
    @State private var lastResizeUpdate = 0.0
    @State private var closeExpanded = true
    @State private var keepExpanded = true
    @State private var draggingNavigationSection: PanelSection?
    @State private var navigationDragStartIndex: Int?
    @State private var navigationDragTargetIndex: Int?
    @State private var navigationDragTranslation: CGFloat = 0
    @State private var navigationDragSettling = false

    private let sectionMovement = Animation.spring(response: 0.30, dampingFraction: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.customizingSections {
                Divider().padding(.horizontal, 18)
                SectionCustomizer(model: model)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                Spacer(minLength: 0)
            } else {
                navigation
                Divider().padding(.horizontal, 18)
                Group {
                    switch model.section {
                    case .openApps: OpenAppsView(model: model)
                    case .profiles: ProfilesView(model: model, closeExpanded: $closeExpanded,
                                                 keepExpanded: $keepExpanded)
                    case .drives: DrivesView(manager: drives,
                                             confirmBeforeQuitting: model.state.preferences.confirmBeforeQuitting)
                    }
                }
                if model.message != nil || model.pendingForceQuitCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        if let message = model.message {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle").foregroundStyle(Palette.accentForeground(model.state.preferences))
                                Text(message).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Button { model.message = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).accessibilityLabel("Dismiss message")
                            }
                        }
                        if model.pendingForceQuitCount > 0 {
                            Button { model.forceQuitRemaining() } label: {
                                Label("Force Quit \(model.pendingForceQuitCount) Remaining", systemImage: "exclamationmark.triangle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                            .disabled(model.busy)
                            .help("Force quit apps from the last run that are still open. Unsaved changes may be lost.")
                        }
                    }
                    .font(.caption)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    .padding([.horizontal, .bottom], 14)
                }
                if let release = updates.availableRelease {
                    UpdateNotice(release: release, preferences: model.state.preferences,
                                 dismiss: { updates.dismiss() })
                    .transition(.opacity)
                }
            }
        }
        .frame(width: model.state.preferences.windowWidth, height: model.state.preferences.windowHeight)
        .background(AdjustableGlass(transparency: model.state.preferences.windowTransparency,
                                    enabled: model.state.preferences.useGlass))
        .preferredColorScheme(colorScheme)
        .tint(Palette.accentForeground(model.state.preferences))
        .animation(.easeInOut(duration: 0.18), value: model.customizingSections)
        .animation(.easeInOut(duration: 0.18), value: updates.availableRelease)
        .overlay(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .help("Drag to resize the panel")
                .accessibilityElement()
                .accessibilityLabel("Resize QuitBatch")
                .accessibilityValue("\(Int(model.state.preferences.windowWidth)) by \(Int(model.state.preferences.windowHeight)) points")
                .accessibilityAdjustableAction { direction in
                    let change: Double = direction == .increment ? 20 : -20
                    model.resizePopover(width: model.state.preferences.windowWidth + change,
                                        height: model.state.preferences.windowHeight + change,
                                        persist: true)
                }
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
                .foregroundStyle(Palette.accentForeground(model.state.preferences))
                .frame(width: ChromeIconMetrics.brand, height: ChromeIconMetrics.brand)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("QuitBatch").font(.system(size: 18, weight: .semibold))
                Text("Apps, profiles, and drives")
                    .font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").font(.system(size: ChromeIconMetrics.action)) }
                .buttonStyle(.borderless)
                .help("Refresh running apps")
                .accessibilityLabel("Refresh running apps")
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: ChromeIconMetrics.action)) }
                .buttonStyle(.borderless)
                .help("Open Settings")
                .accessibilityLabel("Open Settings")
            Button(action: closePanel) { Image(systemName: "xmark").font(.system(size: ChromeIconMetrics.action)) }
                .buttonStyle(.borderless)
                .help("Close QuitBatch panel")
                .accessibilityLabel("Close QuitBatch panel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 15)
    }

    private func dragNavigation(_ value: DragGesture.Value, pitch: CGFloat) {
        let visible = model.visibleSections
        guard visible.count > 1, !navigationDragSettling else { return }
        if draggingNavigationSection == nil {
            let start = min(visible.count - 1, max(0, Int((value.startLocation.x - 4) / pitch)))
            draggingNavigationSection = visible[start]
            navigationDragStartIndex = start
            navigationDragTargetIndex = start
        }
        guard let start = navigationDragStartIndex else { return }
        navigationDragTranslation = ReorderMath.clampedTranslation(value.translation.width,
                                                                    from: start, pitch: pitch, count: visible.count)
        let destination = ReorderMath.destination(startIndex: start,
                                                  translation: navigationDragTranslation, pitch: pitch,
                                                  count: visible.count)
        if destination != navigationDragTargetIndex {
            withAnimation(sectionMovement) { navigationDragTargetIndex = destination }
        }
    }

    private func finishNavigationDrag(pitch: CGFloat) {
        guard let section = draggingNavigationSection,
              let start = navigationDragStartIndex,
              let destination = navigationDragTargetIndex else { return }
        navigationDragSettling = true
        withAnimation(sectionMovement) {
            navigationDragTranslation = CGFloat(destination - start) * pitch
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if destination != start {
                    let visible = model.visibleSections
                    if visible.indices.contains(destination),
                       let fullIndex = model.state.preferences.sectionOrder.firstIndex(of: visible[destination]) {
                        model.moveSection(section, to: fullIndex)
                    }
                }
                draggingNavigationSection = nil
                navigationDragStartIndex = nil
                navigationDragTargetIndex = nil
                navigationDragTranslation = 0
                navigationDragSettling = false
            }
        }
    }

    private var navigation: some View {
        GeometryReader { geometry in
          let visible = model.visibleSections
          let pitch = (geometry.size.width - 8 - CGFloat(max(0, visible.count - 1)) * 5)
              / CGFloat(max(1, visible.count)) + 5
          HStack(spacing: 5) {
            ForEach(Array(visible.enumerated()), id: \.element) { index, section in
                Button {
                    model.section = section
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.symbol).font(.system(size: ChromeIconMetrics.section))
                        Text(section.title)
                            .font(.system(size: 13, weight: model.section == section ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(draggingNavigationSection == section
                                      ? Color(nsColor: .windowBackgroundColor) : .clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(model.section == section ? Color.primary.opacity(0.09) : .clear)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(Color.primary.opacity(draggingNavigationSection == section ? 0.16 : 0),
                                                      lineWidth: 1)
                                }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
                .offset(x: draggingNavigationSection == section ? navigationDragTranslation
                        : navigationDragStartIndex.flatMap { source in
                            navigationDragTargetIndex.map { destination in
                                ReorderMath.shift(index: index, from: source, to: destination, pitch: pitch)
                            }
                        } ?? 0)
                .zIndex(draggingNavigationSection == section ? 2 : 0)
                .shadow(color: .black.opacity(draggingNavigationSection == section ? 0.22 : 0),
                        radius: 7, y: 3)
                .transaction { transaction in
                    if draggingNavigationSection == section && !navigationDragSettling {
                        transaction.animation = nil
                    }
                }
                .help("Drag to reorder sections")
            }
          }
          .padding(4)
          .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
          .contentShape(RoundedRectangle(cornerRadius: 12))
          .simultaneousGesture(
              DragGesture(minimumDistance: 6)
                  .onChanged { dragNavigation($0, pitch: pitch) }
                  .onEnded { _ in finishNavigationDrag(pitch: pitch) }
          )
          .animation(sectionMovement, value: navigationDragTargetIndex)
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
}

struct UpdateNotice: View {
    let release: AvailableRelease
    let preferences: Preferences
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 16))
                .foregroundStyle(Palette.accentForeground(preferences))
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available").font(.caption.weight(.semibold))
                Text("QuitBatch \(release.tag)").font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("View") { NSWorkspace.shared.open(release.url) }
                .buttonStyle(.borderless)
                .accessibilityLabel("View QuitBatch \(release.tag) release")
                .help("Open release page")
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Dismiss update notice")
                .help("Dismiss this version")
        }
        .padding(11)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

private struct SectionCustomizer: View {
    @ObservedObject var model: AppModel
    @State private var draggingSection: PanelSection?
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragSettling = false

    private let movement = Animation.spring(response: 0.30, dampingFraction: 0.86)
    private let rowPitch: CGFloat = 44

    private func move(_ section: PanelSection, to destination: Int) {
        guard !dragSettling, let start = model.state.preferences.sectionOrder.firstIndex(of: section) else { return }
        draggingSection = section
        dragStartIndex = start
        dragTargetIndex = destination
        settleDrag()
    }

    private func drag(_ value: DragGesture.Value) {
        let order = model.state.preferences.sectionOrder
        guard !order.isEmpty, !dragSettling else { return }
        if draggingSection == nil {
            let start = min(order.count - 1, max(0, Int(value.startLocation.y / rowPitch)))
            guard value.startLocation.y - CGFloat(start) * rowPitch <= 32 else { return }
            draggingSection = order[start]
            dragStartIndex = start
            dragTargetIndex = start
        }
        guard let dragStartIndex else { return }
        dragTranslation = ReorderMath.clampedTranslation(value.translation.height,
                                                        from: dragStartIndex, pitch: rowPitch, count: order.count)
        let destination = ReorderMath.destination(startIndex: dragStartIndex,
                                                  translation: dragTranslation, pitch: rowPitch,
                                                  count: order.count)
        if destination != dragTargetIndex {
            withAnimation(movement) { dragTargetIndex = destination }
        }
    }

    private func settleDrag() {
        guard let section = draggingSection,
              let start = dragStartIndex,
              let destination = dragTargetIndex else { return }
        dragSettling = true
        withAnimation(movement) {
            dragTranslation = CGFloat(destination - start) * rowPitch
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if destination != start { model.moveSection(section, to: destination) }
                draggingSection = nil
                dragStartIndex = nil
                dragTargetIndex = nil
                dragTranslation = 0
                dragSettling = false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sections").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { model.customizingSections = false }
                    .buttonStyle(.borderless)
            }
            Text("Drag to reorder or hide a section.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 12) {
              ForEach(Array(model.state.preferences.sectionOrder.enumerated()), id: \.element) { index, section in
                HStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Image(systemName: section.symbol)
                        .frame(width: 19)
                    Text(section.title)
                    Spacer()
                    Toggle(section.title, isOn: Binding(
                        get: { !model.state.preferences.hiddenSections.contains(section) },
                        set: { model.setSectionVisible(section, visible: $0) }
                    ))
                    .labelsHidden()
                    .disabled(model.visibleSections.count == 1 &&
                              !model.state.preferences.hiddenSections.contains(section))
                }
                .frame(height: 32)
                .padding(.horizontal, 9)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(draggingSection == section ? 0.16 : 0), lineWidth: 1))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: "Move up") {
                    guard let index = model.state.preferences.sectionOrder.firstIndex(of: section), index > 0 else { return }
                    move(section, to: index - 1)
                }
                .accessibilityAction(named: "Move down") {
                    guard let index = model.state.preferences.sectionOrder.firstIndex(of: section),
                          index < model.state.preferences.sectionOrder.count - 1 else { return }
                    move(section, to: index + 1)
                }
                .offset(y: draggingSection == section ? dragTranslation
                        : dragStartIndex.flatMap { source in
                            dragTargetIndex.map { destination in
                                ReorderMath.shift(index: index, from: source, to: destination, pitch: rowPitch)
                            }
                        } ?? 0)
                .zIndex(draggingSection == section ? 2 : 0)
                .shadow(color: .black.opacity(draggingSection == section ? 0.22 : 0), radius: 7, y: 3)
                .transaction { transaction in
                    if draggingSection == section && !dragSettling { transaction.animation = nil }
                }
              }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag($0) }
                    .onEnded { _ in settleDrag() }
            )
        }
        .animation(movement, value: dragTargetIndex)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SortOrderCustomizer: View {
    @ObservedObject var model: AppModel
    @Binding var isPresented: Bool
    @State private var draggingMode: AppSortMode?
    @State private var dragStartIndex: Int?
    @State private var dragTargetIndex: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var dragSettling = false

    private let movement = Animation.spring(response: 0.30, dampingFraction: 0.86)
    private let rowPitch: CGFloat = 39

    private func move(_ mode: AppSortMode, to destination: Int) {
        guard !dragSettling, let start = model.state.preferences.appSortOrder.firstIndex(of: mode) else { return }
        draggingMode = mode
        dragStartIndex = start
        dragTargetIndex = destination
        settleDrag()
    }

    private func drag(_ value: DragGesture.Value) {
        let order = model.state.preferences.appSortOrder
        guard !order.isEmpty, !dragSettling else { return }
        if draggingMode == nil {
            let start = min(order.count - 1, max(0, Int(value.startLocation.y / rowPitch)))
            guard value.startLocation.y - CGFloat(start) * rowPitch <= 32 else { return }
            draggingMode = order[start]
            dragStartIndex = start
            dragTargetIndex = start
        }
        guard let dragStartIndex else { return }
        dragTranslation = ReorderMath.clampedTranslation(value.translation.height,
                                                        from: dragStartIndex, pitch: rowPitch, count: order.count)
        let destination = ReorderMath.destination(startIndex: dragStartIndex,
                                                  translation: dragTranslation, pitch: rowPitch,
                                                  count: order.count)
        if destination != dragTargetIndex {
            withAnimation(movement) { dragTargetIndex = destination }
        }
    }

    private func settleDrag() {
        guard let mode = draggingMode,
              let start = dragStartIndex,
              let destination = dragTargetIndex else { return }
        dragSettling = true
        withAnimation(movement) {
            dragTranslation = CGFloat(destination - start) * rowPitch
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if destination != start { model.moveAppSortMode(mode, to: destination) }
                draggingMode = nil
                dragStartIndex = nil
                dragTargetIndex = nil
                dragTranslation = 0
                dragSettling = false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Button order").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done") { withAnimation(.easeInOut(duration: 0.18)) { isPresented = false } }
                    .buttonStyle(.borderless)
            }
            Text("Drag to rearrange the sort buttons.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 7) {
              ForEach(Array(model.state.preferences.appSortOrder.enumerated()), id: \.element) { index, mode in
                HStack(spacing: 9) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(mode.title)
                    Spacer()
                }
                .frame(height: 32)
                .padding(.horizontal, 9)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(draggingMode == mode ? 0.16 : 0), lineWidth: 1))
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityAction(named: "Move up") {
                    guard let index = model.state.preferences.appSortOrder.firstIndex(of: mode), index > 0 else { return }
                    move(mode, to: index - 1)
                }
                .accessibilityAction(named: "Move down") {
                    guard let index = model.state.preferences.appSortOrder.firstIndex(of: mode),
                          index < model.state.preferences.appSortOrder.count - 1 else { return }
                    move(mode, to: index + 1)
                }
                .offset(y: draggingMode == mode ? dragTranslation
                        : dragStartIndex.flatMap { source in
                            dragTargetIndex.map { destination in
                                ReorderMath.shift(index: index, from: source, to: destination, pitch: rowPitch)
                            }
                        } ?? 0)
                .zIndex(draggingMode == mode ? 2 : 0)
                .shadow(color: .black.opacity(draggingMode == mode ? 0.22 : 0), radius: 7, y: 3)
                .transaction { transaction in
                    if draggingMode == mode && !dragSettling { transaction.animation = nil }
                }
              }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { drag($0) }
                    .onEnded { _ in settleDrag() }
            )
        }
        .animation(movement, value: dragTargetIndex)
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}

private struct OpenAppsView: View {
    @ObservedObject var model: AppModel
    @State private var showResults = false
    @State private var searchText = ""
    @State private var customizingSort = false

    private var sortMode: AppSortMode { model.state.preferences.appSortMode }

    private var visibleApps: [RunningApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? model.apps : model.apps.filter { $0.name.localizedStandardContains(query) }
        return filtered.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            let nameFirst = comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
            switch sortMode {
            case .name: return nameFirst
            case .cpu:
                let left = model.usageByPID[lhs.id]?.cpuPercent ?? -1
                let right = model.usageByPID[rhs.id]?.cpuPercent ?? -1
                return left == right ? nameFirst : left > right
            case .memory:
                let left = model.usageByPID[lhs.id]?.memoryBytes ?? 0
                let right = model.usageByPID[rhs.id]?.memoryBytes ?? 0
                return left == right ? nameFirst : left > right
            }
        }
    }

    private func usageLabel(for app: RunningApp) -> String {
        guard let usage = model.usageByPID[app.id] else { return "Usage unavailable" }
        switch sortMode {
        case .name: return ""
        case .cpu:
            guard let cpu = usage.cpuPercent else { return "Measuring CPU…" }
            return String(format: "%.1f%% CPU", cpu)
        case .memory:
            guard let bytes = usage.memoryBytes else { return "Memory unavailable" }
            return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
        }
    }

    private var visibleSelectedCount: Int {
        visibleApps.filter { model.selectedPIDs.contains($0.id) && !$0.protected }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running applications").font(.headline)
                    Text("\(visibleApps.count) running (\(Set(visibleApps.map { $0.reference.id }).count) apps) · \(model.selectedCount) selected")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Select All") { model.select(visibleApps) }
                    .disabled(visibleSelectedCount == visibleApps.filter { !$0.protected }.count || model.busy)
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
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                Text("Sort by").font(.caption).foregroundStyle(.secondary)
                Picker("Sort running apps", selection: Binding(
                    get: { model.state.preferences.appSortMode },
                    set: { model.selectAppSortMode($0) }
                )) {
                    ForEach(model.state.preferences.appSortOrder) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("CPU shows recent processor use; Memory shows each process's memory footprint.")
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { customizingSort.toggle() }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(customizingSort ? Palette.accent(model.state.preferences) : Color.secondary)
                .accessibilityLabel("Reorder sort buttons")
                .help("Reorder Name, CPU, and Memory")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, customizingSort ? 7 : 10)

            if customizingSort {
                SortOrderCustomizer(model: model, isPresented: $customizingSort)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(visibleApps) { app in
                        HStack(alignment: .center, spacing: 9) {
                            Toggle("", isOn: Binding(
                                get: { model.selectedPIDs.contains(app.id) },
                                set: { _ in model.toggle(app) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .frame(width: 16)
                            .accessibilityLabel(app.name)
                            .disabled(app.protected || model.busy)

                            HStack(alignment: .center, spacing: 10) {
                                Image(nsImage: app.icon)
                                    .resizable().interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: model.state.preferences.openAppsIconSize.artwork,
                                           height: model.state.preferences.openAppsIconSize.artwork)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .lineLimit(1)
                                        .font(.system(size: 13, weight: .medium))
                                    if sortMode != .name {
                                        Text(usageLabel(for: app))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                if app.protected {
                                    Text("Protected").foregroundStyle(.secondary)
                                } else if let result = model.resultByPID[app.id] {
                                    Text(result).foregroundStyle(result == "Still running" ? .orange : .secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !app.protected && !model.busy else { return }
                                model.toggle(app)
                            }
                            if model.resultByPID[app.id] == "Still running" {
                                Button { model.reveal(app) } label: { Image(systemName: "arrow.up.forward.app") }
                                    .buttonStyle(.borderless)
                                    .help("Bring \(app.name) forward to close it manually")
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
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
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(model.lastResults.enumerated()), id: \.offset) { _, entry in
                                    HStack {
                                        Text(entry.name).lineLimit(1)
                                        Spacer()
                                        Text(entry.status).foregroundStyle(entry.status == "Still running" ? .orange : .secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 150)
                        .font(.caption)
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
                Button { model.quitSelected() } label: {
                    PrimaryActionLabel(title: model.busy ? "Quitting Apps…" : "Quit Selected Apps",
                                       symbol: "xmark.app.fill")
                }
                .buttonStyle(SoftActionStyle(color: Palette.accent(model.state.preferences),
                                             textColor: Palette.textOnAccent(model.state.preferences)))
                .disabled(model.selectedCount == 0 || model.busy)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
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
    @State private var showingCompactProfiles = false

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
                                        .font(.system(size: model.state.preferences.profilesIconSize.artwork))
                                        .frame(width: model.state.preferences.profilesIconSize.artwork,
                                               height: model.state.preferences.profilesIconSize.artwork)
                                        .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                                    Text(profile.name).lineLimit(1)
                                }
                                .font(.system(size: 13, weight: model.selectedProfileID == profile.id ? .semibold : .regular))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(model.selectedProfileID == profile.id ?
                                            Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.14) :
                                            Color.primary.opacity(0.04),
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
                Button { showingCompactProfiles.toggle() } label: {
                    HStack(spacing: 8) {
                        if let selected = model.selectedProfile {
                            Image(systemName: selected.validSymbol)
                                .font(.system(size: model.state.preferences.profilesIconSize.artwork))
                                .frame(width: model.state.preferences.profilesIconSize.artwork,
                                       height: model.state.preferences.profilesIconSize.artwork)
                                .foregroundStyle(Palette.foregroundColor(selected.accent, preferences: model.state.preferences))
                            Text(selected.name).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose profile")
                .popover(isPresented: $showingCompactProfiles, arrowEdge: .bottom) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.state.profiles) { profile in
                                Button {
                                    model.selectedProfileID = profile.id
                                    editingProfile = false
                                    showingProfileSymbols = false
                                    showingCompactProfiles = false
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: profile.validSymbol)
                                            .font(.system(size: model.state.preferences.profilesIconSize.artwork))
                                            .frame(width: model.state.preferences.profilesIconSize.artwork,
                                                   height: model.state.preferences.profilesIconSize.artwork)
                                            .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                                        Text(profile.name).lineLimit(1)
                                        Spacer(minLength: 4)
                                        if model.selectedProfileID == profile.id {
                                            Image(systemName: "checkmark").font(.caption.weight(.semibold))
                                        }
                                    }
                                    .padding(8)
                                    .background(model.selectedProfileID == profile.id ?
                                                Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13) :
                                                Color.clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                    .frame(width: 270, height: min(280, CGFloat(model.state.profiles.count) *
                          (model.state.preferences.profilesIconSize.artwork + 22) + 16))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 7)
            }

            if let profile = model.selectedProfile {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        profileIdentity(profile)

                        profileAppSection("Close", entries: profile.close, profile: profile, decision: .close)
                        profileAppSection("Keep Open", entries: profile.keep, profile: profile, decision: .keep)

                        VStack(alignment: .leading, spacing: 8) {
                            profileToggle("Include newly detected apps", value: profile.includeNewApps, id: profile.id) { $0.includeNewApps = $1 }
                            Text(profile.includeNewApps
                                 ? "Other running apps close unless saved in Keep Open. Protected apps stay open."
                                 : "Only apps saved in Close will close. Protected apps stay open.")
                                .font(.caption2).foregroundStyle(.secondary)
                            profileToggle("Quit QuitBatch after running", value: profile.quitAfterRunning, id: profile.id) { $0.quitAfterRunning = $1 }
                            profileToggle("Offer workspace restoration after reopening", value: profile.restoreAfterReopening, id: profile.id) { $0.restoreAfterReopening = $1 }
                        }
                        .font(.caption)

                        if !model.state.restorableApps.isEmpty {
                            Button("Restore Previous Workspace") { model.restoreWorkspace() }
                                .disabled(model.busy)
                        }
                    }
                    .padding(16)
                }
                .tint(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))

                Button { model.activateProfile(profile.id) } label: {
                    PrimaryActionLabel(title: "Run \(profile.name.isEmpty ? "Profile" : profile.name)",
                                       symbol: "play.fill")
                }
                .buttonStyle(SoftActionStyle(color: Palette.color(profile.accent, preferences: model.state.preferences),
                                             textColor: Palette.textOnColor(profile.accent, preferences: model.state.preferences)))
                .disabled(model.busy)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
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
        let runningToClose = model.apps.filter {
            AppPolicy.decision(for: $0.reference, protected: $0.protected, profile: profile) == .close
        }.count
        let runningKept = model.apps.filter {
            AppPolicy.decision(for: $0.reference, protected: $0.protected, profile: profile) == .keep
        }.count
        let protectedCount = model.apps.filter(\.protected).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: profile.validSymbol)
                    .font(.system(size: model.state.preferences.profilesIconSize.artwork,
                                  weight: .medium))
                    .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                    .frame(width: model.state.preferences.profilesIconSize.badge,
                           height: model.state.preferences.profilesIconSize.badge)
                    .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text(profile.name.isEmpty ? "Untitled Profile" : profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button { editingProfile.toggle() } label: {
                    Text(editingProfile ? "Done" : "Edit")
                        .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                }
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
            HStack(spacing: 0) {
                Button { closeExpanded = true } label: {
                    profileActivityLabel("\(runningToClose) to close", symbol: "xmark.circle")
                        .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                }
                .buttonStyle(.plain)
                .help("Show the apps this profile will close now")
                .accessibilityLabel("\(runningToClose) running apps to close. Expand Close")
                Divider().frame(height: 18)
                Button { keepExpanded = true } label: {
                    profileActivityLabel("\(runningKept) kept open", symbol: "checkmark.circle")
                        .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                }
                .buttonStyle(.plain)
                .help("Show apps kept open by this profile")
                .accessibilityLabel("\(runningKept) running apps kept open. Expand Keep Open")
                Divider().frame(height: 18)
                profileActivityLabel("\(protectedCount) protected", symbol: "lock.shield")
                    .foregroundStyle(.secondary)
                    .help("Protected apps cannot be closed by QuitBatch")
            }
            .padding(.vertical, 2)
            .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 8))
            if editingProfile {
                Divider()
                profileEditor(profile)
            }
        }
        .padding(12)
        .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.065),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func profileActivityLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 13))
            Text(title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .contentShape(Rectangle())
    }

    private func profileEditor(_ profile: AppProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Name") {
                TextField("Profile name", text: Binding(
                    get: { model.selectedProfile?.name ?? "" },
                    set: { value in model.updateProfile(profile.id) { $0.name = value } }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                Text("Icon").font(.subheadline)
                Button { showingProfileSymbols.toggle() } label: {
                    Image(systemName: profile.validSymbol)
                        .font(.system(size: model.state.preferences.profilesIconSize.artwork, weight: .medium))
                        .foregroundStyle(Palette.foregroundColor(profile.accent, preferences: model.state.preferences))
                        .frame(width: model.state.preferences.profilesIconSize.badge,
                               height: model.state.preferences.profilesIconSize.badge)
                        .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("Choose profile icon")
                .accessibilityLabel("Choose profile icon")
                .popover(isPresented: $showingProfileSymbols, arrowEdge: .top) {
                    profileSymbolPicker(profile)
                }
                Spacer(minLength: 6)
                Text("Accent").font(.subheadline)
                Menu {
                    ForEach(["blue", "teal", "orange", "purple", "red"], id: \.self) { color in
                        Button {
                            model.updateProfile(profile.id) { $0.accent = color == "blue" ? nil : color }
                        } label: {
                            if (profile.accent ?? "blue") == color {
                                Label(color == "blue" ? "App color" : color.capitalized,
                                      systemImage: "checkmark")
                            } else {
                                Text(color == "blue" ? "App color" : color.capitalized)
                            }
                        }
                    }
                } label: {
                    Text(profile.accent == nil || profile.accent == "blue" ? "App color" : (profile.accent?.capitalized ?? "App color"))
                        .lineLimit(1)
                }
                .controlSize(.small)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Profile accent")
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
                            Image(systemName: choice.id)
                                .font(.system(size: model.state.preferences.profilesIconSize.artwork))
                                .frame(maxWidth: .infinity,
                                       minHeight: max(44, model.state.preferences.profilesIconSize.artwork + 16))
                            .foregroundStyle(profile.symbol == choice.id ? Palette.foregroundColor(profile.accent, preferences: model.state.preferences) : Color.primary)
                            .background(profile.symbol == choice.id ? Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.13) : Color.primary.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose \(choice.title) symbol")
                        .accessibilityRemoveTraits(.isSelected)
                        .accessibilityValue(profile.symbol == choice.id ? "Selected" : "Not selected")
                        .help(choice.title)
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
        HStack(spacing: 10) {
            Text(title)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: Binding(
                get: { value },
                set: { newValue in model.updateProfile(id) { change(&$0, newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileAppSection(_ title: String, entries: [AppReference], profile: AppProfile,
                                   decision: ProfileDecision) -> some View {
        let isExpanded = decision == .close ? $closeExpanded : $keepExpanded
        let runningCounts = Dictionary(grouping: model.eligibleApps, by: { $0.reference.id }).mapValues(\.count)
        let savedIDs = Set((profile.close + profile.keep).map(\.id))
        var seenImplicitIDs = Set<String>()
        let implicitApps = decision == .close ? model.eligibleApps.filter {
            !savedIDs.contains($0.reference.id) &&
            AppPolicy.decision(for: $0.reference, protected: false, profile: profile) == decision &&
            seenImplicitIDs.insert($0.reference.id).inserted
        } : []
        let runningTotal = entries.reduce(0) { $0 + (runningCounts[$1.id] ?? 0) }
            + implicitApps.reduce(0) { $0 + (runningCounts[$1.reference.id] ?? 0) }
        return LazyVStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { isExpanded.wrappedValue.toggle() } label: {
                    HStack(spacing: 8) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text("\(entries.count) saved · \(runningTotal) running")
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
                        Button(app.name) { model.setApp(app.reference, decision: decision, profileID: profile.id) }
                        }
                        Divider()
                    }
                    Button("Choose Application…") { model.addApplication(to: profile.id, decision: decision) }
                } label: { Label("Add App", systemImage: "plus").font(.system(size: 14)) }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }
            if isExpanded.wrappedValue {
                if decision == .close {
                    HStack(spacing: 14) {
                        Button("Select All") { model.selectAllAppsToClose(for: profile.id) }
                            .disabled(model.eligibleApps.isEmpty || model.busy)
                            .help("Add running apps except Keep Open and protected apps")
                        Button("Deselect All") { model.clearAppsToClose(for: profile.id) }
                            .disabled((entries.isEmpty && !profile.includeNewApps) || model.busy)
                        Spacer()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                if entries.isEmpty && implicitApps.isEmpty {
                    Text("No apps added").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack(spacing: 8) {
                            Image(nsImage: ProfileIconCache.image(for: entry))
                                .resizable().interpolation(.high)
                                .scaledToFit()
                                .frame(width: model.state.preferences.profilesIconSize.artwork,
                                       height: model.state.preferences.profilesIconSize.artwork)
                            Text(entry.name).font(.caption).lineLimit(1)
                            Spacer()
                            if let count = runningCounts[entry.id], count > 1 {
                                Text("\(count) running")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Button { model.updateProfile(profile.id) { profile in
                                profile.close.removeAll { $0.id == entry.id }
                                profile.keep.removeAll { $0.id == entry.id }
                            }} label: { Image(systemName: "minus.circle").font(.system(size: 16)) }
                                .buttonStyle(.borderless)
                                .help("Remove \(entry.name) from profile")
                        }
                    }
                    ForEach(implicitApps) { app in
                        HStack(spacing: 8) {
                            Image(nsImage: app.icon)
                                .resizable().interpolation(.high)
                                .scaledToFit()
                                .frame(width: model.state.preferences.profilesIconSize.artwork,
                                       height: model.state.preferences.profilesIconSize.artwork)
                            Text(app.name).font(.caption).lineLimit(1)
                            Text(decision == .close ? "Auto" : "Not saved")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                model.setApp(app.reference,
                                             decision: decision == .close ? .keep : .close,
                                             profileID: profile.id)
                            } label: { Image(systemName: "arrow.left.arrow.right.circle").font(.system(size: 16)) }
                            .buttonStyle(.borderless)
                            .help(decision == .close ? "Keep \(app.name) open" : "Add \(app.name) to Close")
                        }
                    }
                }
                if decision == .keep && !profile.includeNewApps {
                    Text("Other apps stay open unless added to Close.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(11)
        .background(Palette.color(profile.accent, preferences: model.state.preferences).opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 11))
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
    let contentSize: CGSize
    @State private var recording = false
    @State private var showingSymbols = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showingSymbols = true } label: {
                    Image(nsImage: SymbolCatalog.menuBarImage(for: model.state.preferences.menuBarSymbol))
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Palette.accentForeground(model.state.preferences))
                        .frame(width: ChromeIconMetrics.brand, height: ChromeIconMetrics.brand)
                        .frame(width: 36, height: 36)
                        .background(Palette.accent(model.state.preferences).opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .help("Change menu bar icon")
                .accessibilityLabel("Change menu bar icon")
                .popover(isPresented: $showingSymbols, arrowEdge: .bottom) { symbolPicker }

                Text("Settings").font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            Divider()

            ScrollView {
                VStack(spacing: 10) {
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
                        Toggle("Keep panel open with Settings", isOn: Binding(
                            get: { model.state.preferences.keepPanelOpenWithSettings },
                            set: { value in model.updatePreferences { $0.keepPanelOpenWithSettings = value } }
                        ))
                        .help("Show Settings beside the QuitBatch panel")
                        Toggle("Launch at login", isOn: Binding(
                            get: { model.state.preferences.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        Toggle("Confirm before quitting apps", isOn: Binding(
                            get: { model.state.preferences.confirmBeforeQuitting },
                            set: { value in model.updatePreferences { $0.confirmBeforeQuitting = value } }
                        ))
                        Toggle("Force quit apps that stay open", isOn: Binding(
                            get: { model.state.preferences.forceQuitUnresponsiveApps },
                            set: { value in model.updatePreferences { $0.forceQuitUnresponsiveApps = value } }
                        ))
                        Text("Force quitting can discard unsaved work.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button { NSApp.terminate(nil) } label: {
                            Label("Quit QuitBatch", systemImage: "power")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    card("Layout", symbol: "rectangle.on.rectangle") {
                        iconSizePicker("Apps icons", selection: Binding(
                            get: { model.state.preferences.openAppsIconSize },
                            set: { value in model.updatePreferences { $0.openAppsIconSize = value } }
                        ))
                        iconSizePicker("Profile icons", selection: Binding(
                            get: { model.state.preferences.profilesIconSize },
                            set: { value in model.updatePreferences { $0.profilesIconSize = value } }
                        ))
                        HStack {
                            Spacer()
                            Button { model.resizePopover(width: 400, height: 500, persist: true) } label: {
                                Label("Reset panel size", systemImage: "arrow.counterclockwise")
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .help("Reset the menu panel to its compact size")
                        }
                    }

                    card("Appearance", symbol: "circle.lefthalf.filled") {
                        HStack(spacing: 10) {
                            Text("Theme").font(.subheadline).frame(width: 96, alignment: .leading)
                            HStack(spacing: 2) {
                                ForEach(["system", "light", "dark"], id: \.self) { theme in
                                    let selected = model.state.preferences.appearance == theme
                                    Button {
                                        model.updatePreferences { $0.appearance = theme }
                                    } label: {
                                        Text(theme.capitalized)
                                            .font(.subheadline.weight(selected ? .semibold : .regular))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 5)
                                            .background(selected ? Color.primary.opacity(0.13) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(theme.capitalized) theme")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                            .padding(3)
                            .frame(maxWidth: .infinity)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Theme")
                        }

                        HStack(alignment: .top, spacing: 10) {
                            Text("Accent color").font(.subheadline)
                                .frame(width: 96, alignment: .leading)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 7) {
                                    Text(model.state.preferences.useCustomAccent ? "Custom color" : "System accent")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer(minLength: 4)
                                    if model.state.preferences.useCustomAccent ||
                                        model.state.preferences.accentDarkness != Preferences.defaultAccentDarkness {
                                        Button("Default") {
                                            model.updatePreferences {
                                                $0.useCustomAccent = false
                                                $0.accentDarkness = Preferences.defaultAccentDarkness
                                            }
                                        }
                                        .controlSize(.small)
                                    }
                                }
                                HStack(spacing: 10) {
                                    ColorRampSlider(value: Binding(
                                        get: { model.state.preferences.customAccentHue },
                                        set: { model.setAccentHue($0, persist: false) }
                                    ), gradient: [.red, .orange, .yellow, .green, .cyan, .blue,
                                                  .purple, .pink, .red],
                                       color: Palette.accent(model.state.preferences),
                                       label: "Accent color",
                                       valueDescription: "\(Int((model.state.preferences.customAccentHue * 360).rounded())) degrees",
                                       keyboardStep: 1.0 / 36,
                                       onCommit: { model.save() })
                                    Circle()
                                        .fill(Palette.accent(model.state.preferences))
                                        .frame(width: 17, height: 17)
                                        .frame(width: 38)
                                        .accessibilityLabel("Current accent color")
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Text("Darken color").font(.subheadline)
                                .frame(width: 96, alignment: .leading)
                            ColorRampSlider(value: Binding(
                                get: { model.state.preferences.accentDarkness },
                                set: { model.setAccentDarkness($0, persist: false) }
                            ), gradient: darknessRamp,
                               color: Palette.accent(model.state.preferences),
                               label: "Darken accent color",
                               valueDescription: "\(Int((model.state.preferences.accentDarkness * 100).rounded())) percent",
                               keyboardStep: 0.01,
                               onCommit: { model.save() })
                                .help("Deepens app and profile accents while keeping labels readable")
                            Text("\(Int((model.state.preferences.accentDarkness * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }

                        Divider().padding(.vertical, 2)

                        Toggle("Use Liquid Glass", isOn: Binding(
                            get: { model.state.preferences.useGlass },
                            set: { value in model.updatePreferences { $0.useGlass = value } }
                        ))
                        HStack(spacing: 10) {
                            Text("Transparency").font(.subheadline).frame(width: 96, alignment: .leading)
                            Slider(value: Binding(
                                get: { model.state.preferences.windowTransparency },
                                set: { model.setWindowTransparency($0, persist: false) }
                            ), in: 0...1, onEditingChanged: { editing in
                                if !editing { model.save() }
                            })
                            .accessibilityLabel("Panel transparency")
                            Text("\(Int((model.state.preferences.windowTransparency * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                        .disabled(!model.state.preferences.useGlass)
                        VStack(alignment: .leading, spacing: 3) {
                            Toggle("Show profile list", isOn: Binding(
                                get: { model.state.preferences.showProfileStrip },
                                set: { value in model.updatePreferences { $0.showProfileStrip = value } }
                            ))
                            Text("Shown when you have more than one profile.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
        .frame(width: contentSize.width, height: contentSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(colorScheme)
        .tint(Palette.accentForeground(model.state.preferences))
        .onDisappear { model.save() }
    }

    private var colorScheme: ColorScheme? {
        switch model.state.preferences.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func iconSizePicker(_ title: String, selection: Binding<IconSizeOption>) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.subheadline).frame(width: 96, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(IconSizeOption.allCases) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(selected ? Color.primary.opacity(0.13) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(option.title)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        }
        .frame(height: 32)
    }

    private var darknessRamp: [Color] {
        [0.0, 0.25, 0.5, 0.75, 1.0].map { depth in
            var sample = model.state.preferences
            sample.accentDarkness = depth
            return Palette.accent(sample)
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
                        Image(nsImage: SymbolCatalog.menuBarImage(for: choice.id))
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: ChromeIconMetrics.brand, height: ChromeIconMetrics.brand)
                            .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(model.state.preferences.menuBarSymbol == choice.id ? Palette.accentForeground(model.state.preferences) : Color.primary)
                        .background(model.state.preferences.menuBarSymbol == choice.id ? Palette.accent(model.state.preferences).opacity(0.14) : Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use \(choice.title) menu bar icon")
                    .help(choice.title)
                }
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private func card<Content: View>(_ title: String, symbol: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: ChromeIconMetrics.section, weight: .medium))
                    .frame(width: ChromeIconMetrics.section, height: ChromeIconMetrics.section)
                    .foregroundStyle(Palette.accentForeground(model.state.preferences))
                Text(title).foregroundStyle(.primary)
            }
            .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }
}

private struct ColorRampSlider: View {
    @Binding var value: Double
    @FocusState private var isFocused: Bool
    let gradient: [Color]
    let color: Color
    let label: String
    let valueDescription: String
    let keyboardStep: Double
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let thumbSize: CGFloat = 18
            let travel = max(0, geometry.size.width - thumbSize)

            ZStack(alignment: .leading) {
                LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing)
                .frame(height: 7)
                .clipShape(Capsule())

                Circle()
                    .fill(color)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(
                        color: .black.opacity(isFocused ? 0.24 : 0.16),
                        radius: isFocused ? 3 : 2,
                        y: 1
                    )
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
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            value = max(0, value - keyboardStep)
            onCommit()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            value = min(1, value + keyboardStep)
            onCommit()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueDescription)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + keyboardStep)
            case .decrement: value = max(0, value - keyboardStep)
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

private struct PrimaryActionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}

private struct SoftActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    let textColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? textColor : Color.secondary)
            .padding(.vertical, 11)
            .background(isEnabled ? color : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 11))
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
