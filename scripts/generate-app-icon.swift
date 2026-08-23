#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/TrafficBarIcon.png"
let canvasSize = 1024
let size = CGFloat(canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create bitmap")
}

bitmap.size = NSSize(width: size, height: size)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawArrow(centerX: CGFloat, bottom: CGFloat, top: CGFloat, directionUp: Bool, fill: NSColor) {
    let shaftWidth: CGFloat = 58
    let headWidth: CGFloat = 146
    let headHeight: CGFloat = 112
    let shaftRect: CGRect
    let head = NSBezierPath()

    if directionUp {
        shaftRect = CGRect(
            x: centerX - shaftWidth / 2,
            y: bottom,
            width: shaftWidth,
            height: top - bottom - headHeight + 20
        )
        head.move(to: CGPoint(x: centerX, y: top))
        head.line(to: CGPoint(x: centerX + headWidth / 2, y: top - headHeight))
        head.line(to: CGPoint(x: centerX + shaftWidth / 2, y: top - headHeight))
        head.line(to: CGPoint(x: centerX + shaftWidth / 2, y: top - headHeight - 18))
        head.line(to: CGPoint(x: centerX - shaftWidth / 2, y: top - headHeight - 18))
        head.line(to: CGPoint(x: centerX - shaftWidth / 2, y: top - headHeight))
        head.line(to: CGPoint(x: centerX - headWidth / 2, y: top - headHeight))
    } else {
        shaftRect = CGRect(
            x: centerX - shaftWidth / 2,
            y: bottom + headHeight - 20,
            width: shaftWidth,
            height: top - bottom - headHeight + 20
        )
        head.move(to: CGPoint(x: centerX, y: bottom))
        head.line(to: CGPoint(x: centerX + headWidth / 2, y: bottom + headHeight))
        head.line(to: CGPoint(x: centerX + shaftWidth / 2, y: bottom + headHeight))
        head.line(to: CGPoint(x: centerX + shaftWidth / 2, y: bottom + headHeight + 18))
        head.line(to: CGPoint(x: centerX - shaftWidth / 2, y: bottom + headHeight + 18))
        head.line(to: CGPoint(x: centerX - shaftWidth / 2, y: bottom + headHeight))
        head.line(to: CGPoint(x: centerX - headWidth / 2, y: bottom + headHeight))
    }

    head.close()
    fill.setFill()
    NSBezierPath(roundedRect: shaftRect, xRadius: shaftWidth / 2, yRadius: shaftWidth / 2).fill()
    head.fill()
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create graphics context")
}
NSGraphicsContext.current = context
context.cgContext.setShouldAntialias(true)
context.cgContext.setAllowsAntialiasing(true)

NSColor.clear.setFill()
CGRect(x: 0, y: 0, width: size, height: size).fill()

// A restrained graphite tile: no gradient, glow, orbit, or decorative particles.
let tileRect = CGRect(x: 88, y: 88, width: 848, height: 848)
let tileRadius: CGFloat = 190
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tileRadius, yRadius: tileRadius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0, 0, 0, 0.30)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
color(42, 42, 44).setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

tilePath.addClip()
color(42, 42, 44).setFill()
tilePath.fill()

// The two arrows are the only visual language: green download, blue upload.
drawArrow(centerX: 402, bottom: 286, top: 738, directionUp: false, fill: color(48, 209, 88))
drawArrow(centerX: 622, bottom: 286, top: 738, directionUp: true, fill: color(10, 132, 255))

let innerBorder = NSBezierPath(roundedRect: tileRect.insetBy(dx: 10, dy: 10), xRadius: tileRadius - 10, yRadius: tileRadius - 10)
innerBorder.lineWidth = 4
color(255, 255, 255, 0.12).setStroke()
innerBorder.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL, options: .atomic)
