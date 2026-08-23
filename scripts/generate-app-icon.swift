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

func fillCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )).fill()
}

func strokeArc(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    path.lineCapStyle = .round
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

func drawArrow(centerX: CGFloat, bottom: CGFloat, top: CGFloat, directionUp: Bool, fill: NSColor) {
    let shaftWidth: CGFloat = 72
    let headWidth: CGFloat = 178
    let headHeight: CGFloat = 142

    let shaftRect: CGRect
    let head = NSBezierPath()

    if directionUp {
        shaftRect = CGRect(
            x: centerX - shaftWidth / 2,
            y: bottom,
            width: shaftWidth,
            height: top - bottom - headHeight + 24
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
            y: bottom + headHeight - 24,
            width: shaftWidth,
            height: top - bottom - headHeight + 24
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

let outerRect = CGRect(x: 74, y: 74, width: 876, height: 876)
let outerRadius: CGFloat = 206
let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: outerRadius, yRadius: outerRadius)

NSGraphicsContext.saveGraphicsState()
let outerShadow = NSShadow()
outerShadow.shadowColor = color(0, 0, 0, 0.42)
outerShadow.shadowBlurRadius = 34
outerShadow.shadowOffset = NSSize(width: 0, height: -18)
outerShadow.set()
color(13, 23, 76).setFill()
outerPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
outerPath.addClip()

let backgroundGradient = NSGradient(colorsAndLocations:
    (color(16, 26, 105), 0.0),
    (color(24, 45, 206), 0.46),
    (color(0, 179, 255), 1.0)
)
backgroundGradient?.draw(in: outerRect, angle: 34)

let vignette = NSGradient(colorsAndLocations:
    (color(8, 13, 44, 0), 0.35),
    (color(8, 13, 44, 0.56), 1.0)
)
vignette?.draw(in: outerRect.insetBy(dx: -120, dy: -120), relativeCenterPosition: NSPoint(x: -0.34, y: 0.38))

color(6, 12, 44, 0.34).setFill()
NSBezierPath(roundedRect: outerRect.insetBy(dx: 28, dy: 28), xRadius: outerRadius - 28, yRadius: outerRadius - 28).fill()

let center = CGPoint(x: size / 2, y: size / 2)
strokeArc(center: center, radius: 320, start: 26, end: 149, width: 24, color: color(92, 230, 255, 0.78))
strokeArc(center: center, radius: 320, start: 202, end: 329, width: 24, color: color(73, 115, 255, 0.86))
strokeArc(center: center, radius: 248, start: 42, end: 128, width: 9, color: color(151, 241, 255, 0.23))
strokeArc(center: center, radius: 248, start: 218, end: 309, width: 9, color: color(151, 241, 255, 0.18))

for dot in [
    (CGPoint(x: 267, y: 512), CGFloat(16), color(95, 226, 255, 0.92)),
    (CGPoint(x: 757, y: 512), CGFloat(16), color(95, 226, 255, 0.92)),
    (CGPoint(x: 343, y: 675), CGFloat(9), color(154, 238, 255, 0.58)),
    (CGPoint(x: 682, y: 349), CGFloat(9), color(154, 238, 255, 0.48))
] {
    fillCircle(center: dot.0, radius: dot.1, color: dot.2)
}

for x in [371.0, 653.0] {
    for y in stride(from: 377.0, through: 646.0, by: 62.0) {
        fillCircle(center: CGPoint(x: x, y: CGFloat(y)), radius: 9, color: color(124, 225, 255, 0.5))
    }
}

drawArrow(centerX: 455, bottom: 307, top: 696, directionUp: false, fill: color(72, 217, 255))
drawArrow(centerX: 574, bottom: 328, top: 718, directionUp: true, fill: color(246, 250, 255))

let edgePath = NSBezierPath(roundedRect: outerRect.insetBy(dx: 8, dy: 8), xRadius: outerRadius - 8, yRadius: outerRadius - 8)
edgePath.lineWidth = 16
color(1, 10, 55, 0.72).setStroke()
edgePath.stroke()

let highlightPath = NSBezierPath(roundedRect: outerRect.insetBy(dx: 34, dy: 34), xRadius: outerRadius - 34, yRadius: outerRadius - 34)
highlightPath.lineWidth = 5
color(99, 228, 255, 0.22).setStroke()
highlightPath.stroke()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL, options: .atomic)
