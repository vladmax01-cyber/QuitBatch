import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    #if UI_PREVIEW
    private let model = AppModel(store: StateStore(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("AppCloserPreview-state.json")))
    #else
    private let model = AppModel()
    #endif
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var outsideClickMonitor: Any?
    private var settingsClickMonitor: Any?
    private var suppressStatusReopenUntil = 0.0
    #if UI_PREVIEW
    private var previewWindow: NSWindow?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let button = statusItem.button else { return }
        button.image = SymbolCatalog.menuBarImage(for: model.state.preferences.menuBarSymbol)
        button.toolTip = "QuitBatch · Option-click for profiles"
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Outside clicks are handled below so a status-item click can toggle the panel reliably.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: model.state.preferences.windowWidth,
                                     height: model.state.preferences.windowHeight)
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model) { [weak self] in
            self?.openSettingsWindow()
        } closePanel: { [weak self] in
            self?.dismissPopover()
        })

        model.onShortcutChanged = { [weak self] shortcut in self?.registerShortcut(shortcut) }
        model.onMenuBarSymbolChanged = { [weak self] symbol in
            self?.statusItem.button?.image = SymbolCatalog.menuBarImage(for: symbol)
        }
        model.onSizeChanged = { [weak self] size in
            self?.popover.contentSize = size
            #if UI_PREVIEW
            self?.previewWindow?.setContentSize(size)
            #endif
        }
        registerShortcut(model.state.preferences.shortcut)
        #if UI_PREVIEW
        let window = NSWindow(contentRect: NSRect(x: 300, y: 250,
                                                  width: model.state.preferences.windowWidth,
                                                  height: model.state.preferences.windowHeight),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "QuitBatch Preview"
        window.contentViewController = NSHostingController(rootView: ContentView(model: model) { [weak self] in
            self?.openSettingsWindow()
        } closePanel: { [weak self] in
            self?.previewWindow?.close()
        })
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
        model.setPanelVisible(true)
        #endif
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            showQuickActions()
        } else {
            guard popover.isShown || ProcessInfo.processInfo.systemUptime >= suppressStatusReopenUntil else { return }
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { dismissPopover() }
        else {
            showPopover(relativeTo: button)
        }
    }

    private func dismissPopover() {
        guard popover.isShown else { return }
        suppressStatusReopenUntil = ProcessInfo.processInfo.systemUptime + 0.3
        popover.close()
        model.setPanelVisible(false)
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        model.setPanelVisible(true)
        if let window = popover.contentViewController?.view.window {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                window.alphaValue = 1
            } else {
                window.alphaValue = 0.72
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    window.animator().alphaValue = 1
                }
            }
            window.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
        monitorOutsideClicks()
    }

    private func showQuickActions() {
        guard let button = statusItem.button else { return }
        dismissPopover()
        let menu = NSMenu(title: "QuitBatch Profiles")
        if model.state.profiles.isEmpty {
            let empty = NSMenuItem(title: "No saved profiles", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for profile in model.state.profiles {
            let item = NSMenuItem(title: profile.name.isEmpty ? "Untitled Profile" : profile.name,
                                  action: #selector(runProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.image = NSImage(systemSymbolName: profile.validSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open QuitBatch", action: #selector(openMain), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettingsWindow), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit QuitBatch", action: #selector(quitUtility), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func runProfile(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return }
        model.activateProfile(id)
        if !popover.isShown, let button = statusItem.button {
            model.section = .openApps
            showPopover(relativeTo: button)
        }
    }

    @objc private func openMain() { togglePopover() }
    @objc private func openSettingsWindow() {
        dismissPopover()
        let availableHeight = (NSScreen.main?.visibleFrame.height ?? 760) - 64
        let settingsSize = NSSize(width: 510, height: min(540, max(500, availableHeight)))
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: settingsSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "QuitBatch"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 430, height: 500)
        window.maxSize = NSSize(width: 720, height: 900)
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.setContentSize(settingsSize)
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quitUtility() { NSApp.terminate(nil) }

    private func monitorOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let clickLocation = NSEvent.mouseLocation
            DispatchQueue.main.async {
                guard let self, self.popover.isShown else { return }
                if let button = self.statusItem.button, let window = button.window {
                    let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
                    if buttonFrame.insetBy(dx: -4, dy: -4).contains(clickLocation) { return }
                }
                self.dismissPopover()
            }
        }
        settingsClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.popover.isShown, event.window === self.settingsWindow {
                self.dismissPopover()
            }
            return event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.setPanelVisible(false)
        suppressStatusReopenUntil = ProcessInfo.processInfo.systemUptime + 0.3
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let settingsClickMonitor { NSEvent.removeMonitor(settingsClickMonitor) }
        outsideClickMonitor = nil
        settingsClickMonitor = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        popoverDidClose(notification)
    }

    private func registerShortcut(_ shortcut: Shortcut?) {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler); self.hotKeyHandler = nil }
        guard let shortcut else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let app = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { app.togglePopover() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard status == noErr else {
            model.message = "Could not install shortcut (error \(status))."
            model.updatePreferences { $0.shortcut = nil }
            return
        }
        let keyID = EventHotKeyID(signature: 0x4170436C, id: 1)
        let registration = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, keyID,
                                               GetApplicationEventTarget(), 0, &hotKey)
        if registration != noErr {
            model.message = "Shortcut is unavailable or already in use (error \(registration))."
            model.updatePreferences { $0.shortcut = nil }
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
