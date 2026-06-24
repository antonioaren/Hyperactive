#!/usr/bin/swift
import AppKit

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let outputDir = "Hyperactive/Hyperactive/Assets.xcassets/AppIcon.appiconset"

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded rect background with gradient
    let cornerRadius = s * 0.22
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let path = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Gradient: deep purple to vibrant blue
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.35, green: 0.10, blue: 0.80, alpha: 1.0),
        CGColor(red: 0.20, green: 0.50, blue: 0.95, alpha: 1.0),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Draw cursor arrow (classic macOS pointer shape)
    let margin = s * 0.18
    let cursorW = s * 0.38
    let cursorH = s * 0.58
    let originX = s * 0.28
    let originY = s - margin - cursorH  // from top

    ctx.saveGState()

    // Shadow for depth
    ctx.setShadow(offset: CGSize(width: s * 0.01, height: -s * 0.02), blur: s * 0.04, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.4))

    // Arrow shape
    let arrow = CGMutablePath()
    let ox = originX
    let oy = originY + cursorH  // tip at top-left area

    // Classic pointer: tip, right edge, notch, tail, back to tip
    arrow.move(to: CGPoint(x: ox, y: oy))                                          // tip (top)
    arrow.addLine(to: CGPoint(x: ox, y: oy - cursorH))                             // down left edge
    arrow.addLine(to: CGPoint(x: ox + cursorW * 0.72, y: oy - cursorH * 0.62))     // right to notch area
    arrow.addLine(to: CGPoint(x: ox + cursorW * 1.05, y: oy - cursorH * 1.0))      // tail right-down
    arrow.addLine(to: CGPoint(x: ox + cursorW * 0.75, y: oy - cursorH * 1.05))     // tail inner
    arrow.addLine(to: CGPoint(x: ox + cursorW * 0.48, y: oy - cursorH * 0.68))     // back to notch
    arrow.addLine(to: CGPoint(x: ox + cursorW * 0.28, y: oy - cursorH * 0.60))     // left of notch
    arrow.closeSubpath()

    // White fill
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.addPath(arrow)
    ctx.fillPath()

    ctx.restoreGState()

    // Motion lines (3 small horizontal lines to the right of cursor)
    let lineX = ox + cursorW * 0.75
    let lineStartY = oy - cursorH * 0.15
    let lineSpacing = s * 0.07
    let lineLength = s * 0.18
    let lineWidth = max(s * 0.025, 1.0)

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)

    for i in 0..<3 {
        let y = lineStartY - CGFloat(i) * lineSpacing
        let shortenFactor = 1.0 - CGFloat(i) * 0.2
        ctx.move(to: CGPoint(x: lineX, y: y))
        ctx.addLine(to: CGPoint(x: lineX + lineLength * shortenFactor, y: y))
        ctx.strokePath()
    }

    image.unlockFocus()
    return image
}

// Generate all sizes
for (size, filename) in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        continue
    }
    let path = "\(outputDir)/\(filename)"
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("Generated \(filename) (\(size)x\(size))")
    } catch {
        print("Failed to write \(filename): \(error)")
    }
}

print("Done!")
