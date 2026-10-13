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

        let depth = CGFloat(pow(min(1, max(0, darkness)), 0.85))
        let targetBrightness = min(brightness, darkAppearance ? 0.58 : 0.42)
        let targetSaturation = saturation < 0.12 ? saturation :
            max(saturation, darkAppearance ? 0.82 : 0.88)
        let candidate = NSColor(calibratedHue: hue,
                                saturation: saturation + (targetSaturation - saturation) * depth,
                                brightness: brightness + (targetBrightness - brightness) * depth,
                                alpha: alpha)
        guard darkAppearance, depth > 0 else { return candidate }

        let background = NSColor(calibratedWhite: 0.118, alpha: 1)
        if contrast(candidate, against: background) >= 3 { return candidate }
        let endpoint = contrast(rgb, against: background) >= 3 ? rgb : .white
        return blend(candidate, toward: endpoint, untilContrast: 3, against: background)
    }

    static func readableForeground(_ accent: NSColor, darkAppearance: Bool) -> NSColor {
        let background = NSColor(calibratedWhite: darkAppearance ? 0.118 : 1, alpha: 1)
        guard contrast(accent, against: background) < 4.5 else { return accent }
        return blend(accent, toward: darkAppearance ? .white : .black,
                     untilContrast: 4.5, against: background)
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
