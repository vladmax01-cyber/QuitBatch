import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Expected output PNG path") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size = 1024
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
let outer = NSRect(x: 55, y: 55, width: 914, height: 914)
let shape = NSBezierPath(roundedRect: outer, xRadius: 205, yRadius: 205)
shape.addClip()
NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.29, blue: 0.43, alpha: 1),
           ending: NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.25, alpha: 1))!
    .draw(in: outer, angle: -45)

let back = NSBezierPath(roundedRect: NSRect(x: 205, y: 340, width: 535, height: 400),
                        xRadius: 82, yRadius: 82)
NSColor(calibratedRed: 0.43, green: 0.60, blue: 0.78, alpha: 1).setFill()
back.fill()
NSColor(calibratedRed: 0.72, green: 0.83, blue: 0.91, alpha: 0.8).setStroke()
back.lineWidth = 12
back.stroke()

let frontRect = NSRect(x: 280, y: 245, width: 540, height: 415)
let front = NSBezierPath(roundedRect: frontRect, xRadius: 86, yRadius: 86)
NSColor(calibratedRed: 0.97, green: 0.98, blue: 1, alpha: 1).setFill()
front.fill()

let top = NSBezierPath(roundedRect: NSRect(x: 298, y: 535, width: 504, height: 105),
                       xRadius: 65, yRadius: 65)
NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.97, alpha: 1).setFill()
top.fill()

let mark = NSBezierPath()
mark.lineWidth = 43
mark.lineCapStyle = .round
mark.move(to: NSPoint(x: 475, y: 345))
mark.line(to: NSPoint(x: 625, y: 495))
mark.move(to: NSPoint(x: 625, y: 345))
mark.line(to: NSPoint(x: 475, y: 495))
NSColor(calibratedRed: 0.14, green: 0.25, blue: 0.39, alpha: 1).setStroke()
mark.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode icon") }
try data.write(to: output)
