import AppKit
import CoreText

guard CommandLine.arguments.count == 2 else { exit(2) }

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let proof = root.appendingPathComponent("Proof", isDirectory: true)
let media = root.appendingPathComponent("Media", isDirectory: true)
try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)

for filename in ["Geist.ttf", "GeistMono.ttf"] {
    let url = root.appendingPathComponent("Resources/Fonts/\(filename)")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

extension NSColor {
    convenience init(hex: String) {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        var integer: UInt64 = 0
        Scanner(string: value).scanHexInt64(&integer)
        self.init(
            srgbRed: CGFloat((integer >> 16) & 0xff) / 255,
            green: CGFloat((integer >> 8) & 0xff) / 255,
            blue: CGFloat(integer & 0xff) / 255,
            alpha: 1
        )
    }
}

let paper = NSColor(hex: "#faf9f5")
let ink = NSColor(hex: "#1a1814")
let ink2 = NSColor(hex: "#6b6862")
let darkPaper = NSColor(hex: "#1a1814")
let darkInk = NSColor(hex: "#f0eee5")
let darkInk2 = NSColor(hex: "#a09e96")
let line = NSColor(hex: "#e6e3db")
let darkLine = NSColor(hex: "#2a2820")
let orange = NSColor(hex: "#ff7a3a")

func geist(_ size: CGFloat, semibold: Bool = false) -> NSFont {
    let candidates = semibold
        ? ["Geist-SemiBold", "Geist SemiBold", "Geist"]
        : ["Geist-Regular", "Geist"]
    return candidates.compactMap { NSFont(name: $0, size: size) }.first
        ?? NSFont.systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
}

func mono(_ size: CGFloat) -> NSFont {
    NSFont(name: "GeistMono-Regular", size: size)
        ?? NSFont(name: "Geist Mono", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
}

func image(_ name: String) -> NSImage {
    guard let value = NSImage(contentsOf: proof.appendingPathComponent(name)) else {
        fatalError("Missing screenshot: \(name)")
    }
    return value
}

func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("Could not create bitmap") }
    bitmap.size = NSSize(width: width, height: height)
    return bitmap
}

func canvasRect(_ height: CGFloat, x: CGFloat, top: CGFloat, width: CGFloat, rectHeight: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - rectHeight, width: width, height: rectHeight)
}

func textHeight(_ value: String, width: CGFloat, font: NSFont, lineHeight: CGFloat) -> CGFloat {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
    return ceil((value as NSString).boundingRect(
        with: NSSize(width: width, height: 1_000),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes
    ).height)
}

func drawText(
    _ value: String,
    canvasHeight: CGFloat,
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    font: NSFont,
    color: NSColor,
    lineHeight: CGFloat,
    tracking: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph,
        .kern: tracking,
    ]
    let height = textHeight(value, width: width, font: font, lineHeight: lineHeight)
    (value as NSString).draw(
        in: canvasRect(canvasHeight, x: x, top: top, width: width, rectHeight: height),
        withAttributes: attributes
    )
}

func drawMark(canvasHeight: CGFloat, x: CGFloat, top: CGFloat, size: CGFloat) {
    orange.setFill()
    NSBezierPath(
        roundedRect: canvasRect(canvasHeight, x: x, top: top, width: size, rectHeight: size),
        xRadius: size * 0.18,
        yRadius: size * 0.18
    ).fill()
}

func drawScreenshot(
    _ screenshot: NSImage,
    canvasHeight: CGFloat,
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    border: NSColor
) {
    let height = width * 1240 / 640
    let rect = canvasRect(canvasHeight, x: x, top: top, width: width, rectHeight: height)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = ink.withAlphaComponent(0.13)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -7)
    shadow.set()
    NSColor.windowBackgroundColor.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    screenshot.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    border.setStroke()
    shape.lineWidth = 1
    shape.stroke()
}

func drawPanel(
    _ screenshot: NSImage,
    canvasHeight: CGFloat,
    x: CGFloat,
    top: CGFloat,
    width: CGFloat,
    border: NSColor
) {
    let height = width * 1052 / 1080
    let rect = canvasRect(canvasHeight, x: x, top: top, width: width, rectHeight: height)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    screenshot.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    border.setStroke()
    shape.lineWidth = 1
    shape.stroke()
}

func render(width: Int, height: Int, background: NSColor, draw: (CGFloat) -> Void) -> Data {
    let bitmap = makeBitmap(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw(CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

let light = image("refill-light.png")
let dark = image("refill-dark.png")
let settingsLight = image("settings-light.png")
let settingsDark = image("settings-dark.png")
let reauthLight = image("reauth-light.png")
let reauthDark = image("reauth-dark.png")

let hero = render(width: 1600, height: 900, background: paper) { height in
    drawScreenshot(light, canvasHeight: height, x: 336, top: 24, width: 440, border: line)
    drawScreenshot(dark, canvasHeight: height, x: 824, top: 24, width: 440, border: darkLine)
}
try hero.write(to: media.appendingPathComponent("hero.png"), options: .atomic)

let social = render(width: 1280, height: 640, background: paper) { height in
    drawScreenshot(light, canvasHeight: height, x: 324, top: 29, width: 300, border: line)
    drawScreenshot(dark, canvasHeight: height, x: 656, top: 29, width: 300, border: darkLine)
}
try social.write(to: media.appendingPathComponent("social-preview.png"), options: .atomic)

let settings = render(width: 1600, height: 900, background: paper) { height in
    drawMark(canvasHeight: height, x: 72, top: 48, size: 16)
    drawText("Every account stays separate.", canvasHeight: height, x: 102, top: 39, width: 900,
             font: geist(24, semibold: true), color: ink, lineHeight: 30)
    drawText("Rename, reauthenticate, or add another login without merging provider homes.",
             canvasHeight: height, x: 72, top: 91, width: 900,
             font: geist(15), color: ink2, lineHeight: 22)
    drawPanel(settingsLight, canvasHeight: height, x: 72, top: 154, width: 704, border: line)
    drawPanel(settingsDark, canvasHeight: height, x: 824, top: 154, width: 704, border: darkLine)
}
try settings.write(to: media.appendingPathComponent("accounts.png"), options: .atomic)

let reauthentication = render(width: 1600, height: 1000, background: darkPaper) { height in
    drawMark(canvasHeight: height, x: 92, top: 84, size: 18)
    drawText("Reauthenticate the right account.", canvasHeight: height, x: 126, top: 75, width: 650,
             font: geist(24, semibold: true), color: darkInk, lineHeight: 30)
    drawText("Refill opens the matching CLI login in Terminal and keeps that account isolated.",
             canvasHeight: height, x: 92, top: 130, width: 650,
             font: geist(17), color: darkInk2, lineHeight: 26)
    drawScreenshot(reauthLight, canvasHeight: height, x: 410, top: 216, width: 360, border: line)
    drawScreenshot(reauthDark, canvasHeight: height, x: 830, top: 216, width: 360, border: darkLine)
}
try reauthentication.write(to: media.appendingPathComponent("reauthentication.png"), options: .atomic)

let iconSource = NSImage(contentsOf: root.appendingPathComponent("build/AppIcon-1024.png"))!
let icon = render(width: 512, height: 512, background: paper) { height in
    iconSource.draw(in: NSRect(x: 0, y: 0, width: 512, height: height))
}
try icon.write(to: media.appendingPathComponent("app-icon.png"), options: .atomic)
