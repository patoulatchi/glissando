import AppKit

guard CommandLine.arguments.count == 2 else { exit(1) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(srgbRed: 0.13, green: 0.32, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.09, y: p * 0.09, width: p * 0.82, height: p * 0.82),
                     xRadius: p * 0.18, yRadius: p * 0.18).fill()
        let config = NSImage.SymbolConfiguration(pointSize: p * 0.46, weight: .medium)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            symbol.draw(in: NSRect(x: p * 0.26, y: p * 0.26, width: p * 0.48, height: p * 0.48))
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
