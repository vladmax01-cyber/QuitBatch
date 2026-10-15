import Foundation

enum SettingsWindowLayout {
    static let preferredWidth: CGFloat = 360
    static let preferredHeight: CGFloat = 450

    static func contentSize(in visibleFrame: CGRect) -> CGSize {
        CGSize(width: preferredWidth,
               height: min(preferredHeight, max(1, visibleFrame.height - 36)))
    }
}

enum WindowPlacement {
    static func beside(_ panel: CGRect, size: CGSize, in visibleFrame: CGRect,
                       gap: CGFloat = 10) -> CGRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        let leftX = panel.minX - gap - width
        let rightX = panel.maxX + gap
        let fitsLeft = leftX >= visibleFrame.minX
        let fitsRight = rightX + width <= visibleFrame.maxX

        let x: CGFloat
        if fitsLeft && (!fitsRight || panel.minX - visibleFrame.minX >= visibleFrame.maxX - panel.maxX) {
            x = leftX
        } else if fitsRight {
            x = rightX
        } else {
            let preferred = panel.minX - visibleFrame.minX >= visibleFrame.maxX - panel.maxX
                ? leftX : rightX
            x = min(max(preferred, visibleFrame.minX), visibleFrame.maxX - width)
        }

        let alignedY = panel.maxY - height
        let y = min(max(alignedY, visibleFrame.minY), visibleFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
