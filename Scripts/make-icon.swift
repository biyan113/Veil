// 渲染应用图标：深色渐变圆角方块 + 半掩的菜单栏条
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.22, alpha: 1),
                        NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.08, alpha: 1)])!
        .draw(in: shape, angle: -90)
    NSColor(white: 1, alpha: 0.08).setStroke()
    shape.lineWidth = s * 0.006
    shape.stroke()

    // 菜单栏条
    let bar = NSRect(x: rect.minX + s * 0.1, y: rect.midY - s * 0.06, width: rect.width - s * 0.2, height: s * 0.12)
    NSColor(white: 1, alpha: 0.10).setFill()
    NSBezierPath(roundedRect: bar, xRadius: s * 0.06, yRadius: s * 0.06).fill()
    // 图标点：左侧淡出，右侧清晰
    let dots = 6
    for i in 0..<dots {
        let d = s * 0.055
        let x = bar.minX + s * 0.05 + CGFloat(i) * (bar.width - s * 0.1 - d) / CGFloat(dots - 1)
        let alpha = i < 3 ? 0.18 + 0.08 * Double(i) : 0.95
        NSColor(white: 1, alpha: alpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: bar.midY - d / 2, width: d, height: d)).fill()
    }
    // 分隔线
    let lx = bar.minX + s * 0.05 + 2.5 * (bar.width - s * 0.1 - s * 0.055) / CGFloat(dots - 1) + s * 0.027
    NSColor(calibratedRed: 0.55, green: 0.7, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: lx - s * 0.006, y: bar.minY - s * 0.05, width: s * 0.012, height: bar.height + s * 0.1),
                 xRadius: s * 0.006, yRadius: s * 0.006).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
