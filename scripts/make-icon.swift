// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    // macOS icon grid: 824pt rounded square centered in 1024.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    NSColor(srgbRed: 0.067, green: 0.067, blue: 0.067, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s).fill()

    // The eyebrow: the same brush stroke as the collapsed notch on a 100 × 40 grid (y down), thick head on the left.
    let grid: [CGFloat] = [4, 30, 18, 16, 44, 9, 68, 11, 81, 12, 91, 16, 97, 21,
                           89, 19, 79, 18, 68, 19, 47, 20, 27, 26, 11, 35, 7, 37, 2, 34, 4, 30]
    let k = 5.1 * s
    let point = { (i: Int) in NSPoint(x: body.midX + (grid[2 * i] - 50) * k, y: body.midY - (grid[2 * i + 1] - 22) * k) }
    let brow = NSBezierPath()
    brow.move(to: point(0))
    for curve in 0..<5 {
        let i = 1 + curve * 3
        brow.curve(to: point(i + 2), controlPoint1: point(i), controlPoint2: point(i + 1))
    }
    brow.close()
    NSColor(srgbRed: 0.957, green: 0.957, blue: 0.945, alpha: 1).setFill()
    brow.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/images/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Resources/AppIcon.icns" : "iconutil failed")
