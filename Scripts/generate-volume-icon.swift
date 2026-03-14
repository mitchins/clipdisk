#!/usr/bin/env swift

import AppKit

// Create a simple clipboard icon for the volume
let size = NSSize(width: 512, height: 512)
let image = NSImage(size: size)

image.lockFocus()

// Background circle with gradient
let circle = NSBezierPath(ovalIn: NSRect(x: 56, y: 56, width: 400, height: 400))
let gradient = NSGradient(colors: [
    NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0),
    NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)
])
gradient?.draw(in: circle, angle: -90)

// Clipboard symbol (simple rectangle with rounded top)
NSColor.white.setFill()
let clipboardRect = NSBezierPath(roundedRect: NSRect(x: 156, y: 106, width: 200, height: 300), xRadius: 20, yRadius: 20)
clipboardRect.fill()

// Clip at top
let clipRect = NSBezierPath(roundedRect: NSRect(x: 206, y: 356, width: 100, height: 80), xRadius: 15, yRadius: 15)
NSColor(white: 0.3, alpha: 1.0).setFill()
clipRect.fill()

image.unlockFocus()

// Save as .icns (requires creating iconset first)
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("VolumeIcon.iconset")
try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512]
for size in sizes {
    let resized = NSImage(size: NSSize(width: size, height: size))
    resized.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    resized.unlockFocus()
    
    if let tiff = resized.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        let filename = size > 256 ? "\(size)x\(size)@2x.png" : "\(size)x\(size).png"
        let url = tempDir.appendingPathComponent(filename)
        try? png.write(to: url)
    }
}

// Convert iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", "Resources/VolumeIcon.icns", tempDir.path]
try? process.run()
process.waitUntilExit()

try? FileManager.default.removeItem(at: tempDir)

if process.terminationStatus == 0 {
    print("✓ Created Resources/VolumeIcon.icns")
} else {
    print("✗ Failed to create icon")
}
