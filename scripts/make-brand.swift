// Renders every brand asset from branding/logo.svg.  Run from the project root:
//   swift scripts/make-brand.swift
// Writes Resources/AppIcon.icns, branding/logo.png and branding/social-preview.png.
import AppKit

let fm = FileManager.default
guard let logo = NSImage(contentsOf: URL(fileURLWithPath: "branding/logo.svg")) else {
    print("branding/logo.svg not found"); exit(1)
}

/// Draws into a transparent bitmap of exactly `width` x `height` pixels.
func render(width: Int, height: Int, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The SVG has a 100 px margin inside its 1024 canvas (the macOS icon grid); this draws it so the
/// rounded square fills `rect` exactly.
func drawTight(in rect: NSRect) {
    let scale = 1024.0 / 824.0
    let big = NSRect(x: rect.midX - rect.width * scale / 2, y: rect.midY - rect.height * scale / 2,
                     width: rect.width * scale, height: rect.height * scale)
    logo.draw(in: big)
}

// App icon (.icns), keeping the macOS margin.
let iconset = "build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let data = render(width: px, height: px) { logo.draw(in: NSRect(x: 0, y: 0, width: px, height: px)) }
        try data.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()

// Logo for the README: the rounded square without the margin.
try render(width: 512, height: 512) { drawTight(in: NSRect(x: 0, y: 0, width: 512, height: 512)) }
    .write(to: URL(fileURLWithPath: "branding/logo.png"))

// GitHub social preview, 1280 x 640.
let social = render(width: 1280, height: 640) {
    let canvas = NSRect(x: 0, y: 0, width: 1280, height: 640)
    NSGradient(colors: [NSColor(red: 0.105, green: 0.085, blue: 0.055, alpha: 1), NSColor(red: 0.03, green: 0.025, blue: 0.02, alpha: 1)])!
        .draw(in: canvas, angle: -60)
    NSGradient(colors: [NSColor(red: 0.96, green: 0.80, blue: 0.45, alpha: 0.22), NSColor(red: 0.96, green: 0.80, blue: 0.45, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: 310, y: 320), radius: 0, toCenter: NSPoint(x: 310, y: 320), radius: 460, options: [])
    drawTight(in: NSRect(x: 110, y: 120, width: 400, height: 400))

    let gold = NSColor(red: 0.96, green: 0.82, blue: 0.48, alpha: 1)
    let title = NSAttributedString(string: "Free Buds Manager", attributes: [
        .font: NSFont.systemFont(ofSize: 68, weight: .bold), .foregroundColor: NSColor(white: 0.97, alpha: 1)])
    let subtitle = NSAttributedString(string: "Control your Huawei FreeBuds\nfrom the Mac menu bar", attributes: [
        .font: NSFont.systemFont(ofSize: 40, weight: .medium), .foregroundColor: gold])
    let tag = NSAttributedString(string: "Noise control  ·  Spatial audio  ·  EQ  ·  Gestures", attributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .regular), .foregroundColor: NSColor(white: 0.62, alpha: 1)])
    title.draw(at: NSPoint(x: 572, y: 375))
    subtitle.draw(in: NSRect(x: 580, y: 220, width: 640, height: 130))
    tag.draw(at: NSPoint(x: 580, y: 150))
}
try social.write(to: URL(fileURLWithPath: "branding/social-preview.png"))
print("brand assets written")
