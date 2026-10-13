import AppKit

enum AccentTone {
    static func adjusted(_ base: NSColor, darkness: Double, darkAppearance: Bool) -> NSColor {
        let rgb = base.usingColorSpace(.deviceRGB) ?? base
        guard darkness > 0 else { return rgb }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let depth = CGFloat(min(1, max(0, darkness)))
        let background = NSColor(calibratedWhite: darkAppearance ? 0.118 : 1, alpha: 1)
        let initialContrast = contrast(rgb, against: background)
        let finalContrast = darkAppearance ? min(initialContrast, 3) : max(initialContrast, 9)
        let desiredContrast = initialContrast + (finalContrast - initialContrast) * depth
        let adjustedSaturation = saturation < 0.12 ? saturation :
            saturation + (1 - saturation) * depth * 0.18

        func color(brightness level: CGFloat) -> NSColor {
            NSColor(calibratedHue: hue, saturation: adjustedSaturation,
                    brightness: level, alpha: alpha)
        }

        var lower: CGFloat = 0
        var upper = brightness
        for _ in 0..<14 {
            let middle = (lower + upper) / 2
            let ratio = contrast(color(brightness: middle), against: background)
            if (darkAppearance && ratio > desiredContrast) ||
               (!darkAppearance && ratio < desiredContrast) {
                upper = middle
            } else {
                lower = middle
            }
        }
        return color(brightness: (lower + upper) / 2)
    }

    static func readableForeground(_ accent: NSColor, darkAppearance: Bool) -> NSColor {
        let background = NSColor(calibratedWhite: darkAppearance ? 0.118 : 1, alpha: 1)
        guard contrast(accent, against: background) < 4.5 else { return accent }
        return blend(accent, toward: darkAppearance ? .white : .black,
                     untilContrast: 4.5, against: background)
    }

    static func textOnFill(_ accent: NSColor) -> NSColor {
        contrast(.white, against: accent) >= 4 ? .white : .black
    }

    static func contrast(_ first: NSColor, against second: NSColor) -> CGFloat {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) +
               0.7152 * linear(rgb.greenComponent) +
               0.0722 * linear(rgb.blueComponent)
    }

    private static func blend(_ color: NSColor, toward target: NSColor,
                              untilContrast minimum: CGFloat, against background: NSColor) -> NSColor {
        let source = color.usingColorSpace(.deviceRGB) ?? color
        let destination = target.usingColorSpace(.deviceRGB) ?? target
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        for _ in 0..<14 {
            let fraction = (lower + upper) / 2
            let mixed = NSColor(deviceRed: source.redComponent + (destination.redComponent - source.redComponent) * fraction,
                                green: source.greenComponent + (destination.greenComponent - source.greenComponent) * fraction,
                                blue: source.blueComponent + (destination.blueComponent - source.blueComponent) * fraction,
                                alpha: source.alphaComponent)
            if contrast(mixed, against: background) >= minimum {
                upper = fraction
            } else {
                lower = fraction
            }
        }
        return NSColor(deviceRed: source.redComponent + (destination.redComponent - source.redComponent) * upper,
                       green: source.greenComponent + (destination.greenComponent - source.greenComponent) * upper,
                       blue: source.blueComponent + (destination.blueComponent - source.blueComponent) * upper,
                       alpha: source.alphaComponent)
    }
}
