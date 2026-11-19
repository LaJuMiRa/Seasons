// Draws the Seasons app icon procedurally (no image assets) and writes an .iconset folder.
// Usage: swiftc scripts/make-icon.swift -o make-icon && ./make-icon <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: make-icon <output.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func drawIcon(size: CGFloat, in ctx: CGContext) {
    let s = size
    // Squircle-like rounded square with the standard macOS margin.
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [CGColor(red: 0.13, green: 0.20, blue: 0.42, alpha: 1),
                  CGColor(red: 0.38, green: 0.36, blue: 0.70, alpha: 1),
                  CGColor(red: 0.93, green: 0.62, blue: 0.74, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Snow mound along the bottom.
    ctx.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 1, alpha: 1))
    let mound = CGMutablePath()
    mound.move(to: CGPoint(x: rect.minX, y: rect.minY))
    mound.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.16))
    mound.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
                   control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.3),
                   control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.1))
    mound.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    mound.closeSubpath()
    ctx.addPath(mound)
    ctx.fillPath()

    // Six-armed snowflake.
    let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.06)
    let arm = rect.width * 0.27
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(1, s * 0.03))
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 + .pi / 2
        let dir = CGPoint(x: cos(a), y: sin(a))
        let tip = CGPoint(x: center.x + dir.x * arm, y: center.y + dir.y * arm)
        ctx.move(to: center)
        ctx.addLine(to: tip)
        for (pos, len) in [(0.55, 0.32), (0.8, 0.22)] as [(CGFloat, CGFloat)] {
            let base = CGPoint(x: center.x + dir.x * arm * pos, y: center.y + dir.y * arm * pos)
            for side in [-1.0, 1.0] as [CGFloat] {
                let b = a + side * .pi / 4
                ctx.move(to: base)
                ctx.addLine(to: CGPoint(x: base.x + cos(b) * arm * len, y: base.y + sin(b) * arm * len))
            }
        }
    }
    ctx.strokePath()

    // A falling petal and leaf as seasonal accents.
    func ellipse(_ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ angle: CGFloat, _ color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: angle)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }
    ellipse(CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.22), s * 0.07, s * 0.045, 0.6,
            CGColor(red: 1, green: 0.78, blue: 0.86, alpha: 1))
    ellipse(CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.42), s * 0.08, s * 0.04, -0.7,
            CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1))
    ctx.restoreGState()
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let gc = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    drawIcon(size: CGFloat(px), in: gc.cgContext)
    gc.flushGraphics()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: output.appendingPathComponent("\(name).png"))
}
