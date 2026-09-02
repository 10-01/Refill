import AppKit

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(3) }
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 250 / 255, green: 249 / 255, blue: 245 / 255, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()

let orange = NSColor(calibratedRed: 1, green: 122 / 255, blue: 58 / 255, alpha: 1)
orange.setFill()
NSBezierPath(roundedRect: NSRect(x: 282, y: 282, width: 460, height: 460), xRadius: 44, yRadius: 44).fill()

let ink = NSColor(calibratedRed: 26 / 255, green: 24 / 255, blue: 20 / 255, alpha: 1)
ink.setFill()
NSBezierPath(roundedRect: NSRect(x: 378, y: 574, width: 268, height: 28), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 378, y: 498, width: 190, height: 28), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 378, y: 422, width: 232, height: 28), xRadius: 7, yRadius: 7).fill()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
