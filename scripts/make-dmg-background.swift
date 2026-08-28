import AppKit

let canvasSize = NSSize(width: 660, height: 420)
let backingScale = 2.0

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width * backingScale),
    pixelsHigh: Int(canvasSize.height * backingScale),
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

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGraphicsContext.current?.shouldAntialias = true
NSGraphicsContext.current?.imageInterpolation = .high
context.cgContext.scaleBy(x: backingScale, y: backingScale)

let canvas = NSRect(origin: .zero, size: canvasSize)
let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.965, green: 0.975, blue: 0.972, alpha: 1),
    NSColor(calibratedRed: 0.925, green: 0.946, blue: 0.950, alpha: 1)
])
background?.draw(in: canvas, angle: -90)

func drawCenteredText(
    _ text: String,
    y: CGFloat,
    font: NSFont,
    color: NSColor
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    let rect = NSRect(x: 32, y: y, width: canvasSize.width - 64, height: 42)
    text.draw(in: rect, withAttributes: attributes)
}

drawCenteredText(
    "安装流量管家",
    y: 338,
    font: .systemFont(ofSize: 27, weight: .semibold),
    color: NSColor(calibratedWhite: 0.11, alpha: 1)
)
drawCenteredText(
    "将左侧图标拖到右侧“应用程序”文件夹",
    y: 304,
    font: .systemFont(ofSize: 15, weight: .regular),
    color: NSColor(calibratedWhite: 0.34, alpha: 1)
)

let arrowColor = NSColor(calibratedRed: 0.25, green: 0.58, blue: 1, alpha: 0.9)
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 278, y: 205))
arrow.line(to: NSPoint(x: 382, y: 205))
arrow.move(to: NSPoint(x: 365, y: 220))
arrow.line(to: NSPoint(x: 382, y: 205))
arrow.line(to: NSPoint(x: 365, y: 190))
arrowColor.setStroke()
arrow.stroke()

drawCenteredText(
    "安装完成后，可从“应用程序”中启动",
    y: 51,
    font: .systemFont(ofSize: 13, weight: .regular),
    color: NSColor(calibratedWhite: 0.42, alpha: 1)
)
drawCenteredText(
    "若首次打开被阻止：系统设置 → 隐私与安全性 → 仍要打开",
    y: 24,
    font: .systemFont(ofSize: 12, weight: .regular),
    color: NSColor(calibratedWhite: 0.38, alpha: 1)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(1)
}

let output = CommandLine.arguments.dropFirst().first ?? "dist/TrafficBarInstallerBackground.png"
try png.write(to: URL(fileURLWithPath: output))
