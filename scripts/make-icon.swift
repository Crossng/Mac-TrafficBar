import AppKit

let size = 1024.0
let center = NSPoint(x: size / 2, y: size / 2)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    exit(1)
}
bitmap.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGraphicsContext.current?.shouldAntialias = true
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let backgroundInset = 40.0
let background = NSBezierPath(
    roundedRect: NSRect(
        x: backgroundInset,
        y: backgroundInset,
        width: size - backgroundInset * 2,
        height: size - backgroundInset * 2
    ),
    xRadius: 208,
    yRadius: 208
)
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
background.fill()

let ringDiameter = 584.0
let ring = NSBezierPath(
    ovalIn: NSRect(
        x: center.x - ringDiameter / 2,
        y: center.y - ringDiameter / 2,
        width: ringDiameter,
        height: ringDiameter
    )
)
ring.lineWidth = 68
NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.54, alpha: 1).setStroke()
ring.stroke()

let arrowOffset = 90.0
let arrowStroke = 58.0
let arrowTop = center.y + 174
let arrowBottom = center.y - 174
let arrowHeadInset = 76.0

let downCenterX = center.x - arrowOffset
let arrow = NSBezierPath()
arrow.lineWidth = arrowStroke
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: downCenterX, y: arrowTop))
arrow.line(to: NSPoint(x: downCenterX, y: arrowBottom))
arrow.move(to: NSPoint(x: downCenterX - arrowHeadInset, y: arrowBottom + arrowHeadInset))
arrow.line(to: NSPoint(x: downCenterX, y: arrowBottom))
arrow.line(to: NSPoint(x: downCenterX + arrowHeadInset, y: arrowBottom + arrowHeadInset))
NSColor.white.setStroke()
arrow.stroke()

let upCenterX = center.x + arrowOffset
let up = NSBezierPath()
up.lineWidth = arrowStroke
up.lineCapStyle = .round
up.lineJoinStyle = .round
up.move(to: NSPoint(x: upCenterX, y: arrowBottom))
up.line(to: NSPoint(x: upCenterX, y: arrowTop))
up.move(to: NSPoint(x: upCenterX - arrowHeadInset, y: arrowTop - arrowHeadInset))
up.line(to: NSPoint(x: upCenterX, y: arrowTop))
up.line(to: NSPoint(x: upCenterX + arrowHeadInset, y: arrowTop - arrowHeadInset))
NSColor(calibratedRed: 0.25, green: 0.58, blue: 1, alpha: 1).setStroke()
up.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let output = CommandLine.arguments.dropFirst().first ?? "Resources/TrafficBarIcon.png"
try png.write(to: URL(fileURLWithPath: output))
