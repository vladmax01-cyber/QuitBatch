import AppKit

struct SymbolChoice: Identifiable {
    let id: String
    let title: String
}

enum SymbolCatalog {
    static let profileChoices: [SymbolChoice] = [
        .init(id: "square.stack.3d.up", title: "Apps"),
        .init(id: "xmark.app", title: "Quit"),
        .init(id: "macwindow.on.rectangle", title: "Windows"),
        .init(id: "checkmark.shield", title: "Protected"),
        .init(id: "graduationcap", title: "Exam"),
        .init(id: "moon.stars", title: "Focus"),
        .init(id: "briefcase", title: "Work"),
        .init(id: "gamecontroller", title: "Games"),
        .init(id: "airplane", title: "Travel"),
        .init(id: "music.note", title: "Music"),
        .init(id: "books.vertical", title: "Study"),
        .init(id: "desktopcomputer", title: "Desktop"),
        .init(id: "heart.text.square", title: "Health"),
        .init(id: "cross.case", title: "Care"),
        .init(id: "doc.text", title: "Documents"),
        .init(id: "checklist", title: "Checklist"),
        .init(id: "calendar", title: "Calendar"),
        .init(id: "clock", title: "Time"),
        .init(id: "envelope", title: "Mail"),
        .init(id: "message", title: "Messages"),
        .init(id: "paintbrush", title: "Creative"),
        .init(id: "camera", title: "Photos"),
        .init(id: "globe", title: "Web"),
        .init(id: "lock.shield", title: "Privacy")
    ]

    static let menuBarChoices: [SymbolChoice] = [
        .init(id: "appcloser", title: "QuitBatch"),
        .init(id: "xmark.app", title: "Quit"),
        .init(id: "square.stack.3d.up", title: "Stack"),
        .init(id: "macwindow.on.rectangle", title: "Windows"),
        .init(id: "rectangle.stack", title: "Layers"),
        .init(id: "checkmark.shield", title: "Shield"),
        .init(id: "moon.stars", title: "Focus"),
        .init(id: "briefcase", title: "Work"),
        .init(id: "graduationcap", title: "Study"),
        .init(id: "calendar", title: "Calendar"),
        .init(id: "heart", title: "Health"),
        .init(id: "gearshape", title: "Settings")
    ]

    static func menuBarImage(for choice: String) -> NSImage {
        guard choice != "appcloser",
              menuBarChoices.contains(where: { $0.id == choice }),
              let image = NSImage(systemSymbolName: choice, accessibilityDescription: "QuitBatch") else {
            return customMenuBarImage()
        }
        let configured = image.withSymbolConfiguration(.init(pointSize: 18, weight: .medium)) ?? image
        configured.isTemplate = true
        return configured
    }

    private static func customMenuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: 1.1)
            transform.concat()
            NSColor.black.setStroke()
            let back = NSBezierPath(roundedRect: NSRect(x: 2, y: 6, width: 12, height: 10), xRadius: 2, yRadius: 2)
            back.lineWidth = 1.45
            back.stroke()

            NSColor.black.setFill()
            let front = NSBezierPath(roundedRect: NSRect(x: 5, y: 2, width: 13, height: 11), xRadius: 2, yRadius: 2)
            front.fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setStroke()
            let close = NSBezierPath()
            close.lineWidth = 1.55
            close.lineCapStyle = .round
            close.move(to: NSPoint(x: 10, y: 5.3))
            close.line(to: NSPoint(x: 14, y: 9.4))
            close.move(to: NSPoint(x: 14, y: 5.3))
            close.line(to: NSPoint(x: 10, y: 9.4))
            close.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "QuitBatch"
        return image
    }
}
