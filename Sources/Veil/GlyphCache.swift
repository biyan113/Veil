import AppKit
import CoreVideo
import ScreenCaptureKit

/// 菜单栏图标的真实外观。
/// 图标只有真正显示在屏幕上时才能截到，所以在启动、打开设置页和托盘时顺手截取并缓存（内存 + 磁盘），
/// 被刘海挡住的图标就用上次的缓存。需要「屏幕录制」权限。
@MainActor
final class GlyphCache {
    static let shared = GlyphCache()
    static let didUpdate = Notification.Name("VeilGlyphCacheDidUpdate")

    /// 打开托盘时，距离上次截取超过这么久才重新截
    private static let refreshInterval: TimeInterval = 60
    /// backgroundColor 是 unowned，颜色对象必须一直活着
    private static let captureBackground = CGColor(gray: 0.5, alpha: 1)

    private var images: [String: NSImage] = [:]
    private var isCapturing = false
    private var lastCapture = Date.distantPast
    private let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("net.bytenote.veil")
        // v3 的文件名带进程内随机的哈希，换次启动就找不到了。v4 把透出来的壁纸一起截进去了。
        try? FileManager.default.removeItem(at: base.appendingPathComponent("glyphs-v3"))
        try? FileManager.default.removeItem(at: base.appendingPathComponent("glyphs-v4"))
        let dir = base.appendingPathComponent("glyphs-v5", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 新版系统上 CGPreflightScreenCaptureAccess 并不可靠，以「上一次截取是否成功」为准
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess() || UserDefaults.standard.bool(forKey: "glyphCaptureWorked")
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func image(for item: MenuBarItem) -> NSImage? {
        if let image = images[item.key] { return image }
        guard let data = try? Data(contentsOf: fileURL(item.key)), let rep = NSBitmapImageRep(data: data) else { return nil }
        let scale = CGFloat(UserDefaults.standard.double(forKey: "glyphScale.\(item.key)")).nonZero ?? 2
        let image = Self.makeImage(rep, pointSize: NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale),
                                   template: UserDefaults.standard.bool(forKey: "glyphTemplate.\(item.key)"))
        images[item.key] = image
        return image
    }

    /// 打开托盘时调用：判断遮挡需要全部图标，所以单独做一次完整扫描，不拖慢托盘本身
    func refreshIfStale() {
        guard !isCapturing, Date().timeIntervalSince(lastCapture) > Self.refreshInterval else { return }
        lastCapture = Date()
        Task { await capture(await MenuBarItemScanner.scan()) }
    }

    /// 截取当前真正显示在屏幕上的图标
    func capture(_ items: [MenuBarItem]) async {
        guard !isCapturing, !Self.isMenuBarHiddenBySystem else { return }
        let onScreen = items.filter { Self.isActuallyVisible($0) && !Self.isStacked($0, among: items) }
        guard !onScreen.isEmpty else { return }
        isCapturing = true
        defer { isCapturing = false }
        lastCapture = Date()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            NSLog("Veil: 无法截取菜单栏 \(error)")
            UserDefaults.standard.set(false, forKey: "glyphCaptureWorked")
            return
        }
        var changed = false
        for screen in NSScreen.screens where screen.frame.maxY - screen.visibleFrame.maxY > 1 {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let bounds = CGDisplayBounds(id)
            let mine = onScreen.filter { bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            guard !mine.isEmpty else { continue }

            // 整屏截图会把菜单栏毛玻璃后面的壁纸一起拍进去，去背景时就变成残影。
            // 先只截 Window Server 的菜单栏窗口；背景仍然花的话，垫一层纯色再截整条。
            let scale = screen.backingScaleFactor
            let strip = CGRect(x: 0, y: 0, width: bounds.width,
                               height: ceil(mine.map { $0.frame.maxY - bounds.minY }.max() ?? 24) + 1)
            let barWindow = Self.menuBarWindow(in: content.windows, display: bounds)
            var cropFrame = CGRect(origin: bounds.origin, size: strip.size)
            var shot: CGImage?
            if let barWindow,
               let isolated = await Self.screenshot(of: barWindow, display: display, strip: strip, scale: scale),
               Self.borderSpread(isolated) <= 0.08 {
                shot = isolated
                cropFrame = barWindow.frame
            } else if barWindow != nil {
                NSLog("Veil: 菜单栏窗口仍透出背景，垫纯色重截")
            }
            if shot == nil {
                let backdrop = MenuBarBackdrop()
                backdrop.show()
                await Task.yield()
                try? await Task.sleep(nanoseconds: 160_000_000)
                shot = await Self.screenshot(of: nil, display: display, strip: strip, scale: scale)
                cropFrame = CGRect(origin: bounds.origin, size: strip.size)
                backdrop.hide()
            }
            guard let shot else { continue }
            UserDefaults.standard.set(true, forKey: "glyphCaptureWorked")

            let sx = CGFloat(shot.width) / cropFrame.width
            let sy = CGFloat(shot.height) / cropFrame.height
            let crops: [(key: String, url: URL, image: CGImage)] = mine.compactMap { item in
                let r = item.frame.offsetBy(dx: -cropFrame.minX, dy: -cropFrame.minY)
                let px = CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy).integral
                return shot.cropping(to: px).map { (item.key, fileURL(item.key), $0) }
            }
            // 逐像素处理和写盘放到后台，打开托盘时主线程不被占用
            let glyphs = await Task.detached(priority: .utility) {
                crops.compactMap { crop -> (key: String, png: Data, template: Bool)? in
                    guard let (rep, template) = Self.removeBackground(crop.image),
                          let png = rep.representation(using: .png, properties: [:]) else { return nil }
                    try? png.write(to: crop.url)
                    return (crop.key, png, template)
                }
            }.value

            for (key, png, template) in glyphs {
                guard let rep = NSBitmapImageRep(data: png) else { continue }
                let size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
                images[key] = Self.makeImage(rep, pointSize: size, template: template)
                UserDefaults.standard.set(template, forKey: "glyphTemplate.\(key)")
                UserDefaults.standard.set(Double(scale), forKey: "glyphScale.\(key)")
                changed = true
            }
        }
        if changed { NotificationCenter.default.post(name: Self.didUpdate, object: nil) }
    }

    // MARK: - 私有

    /// 文件名必须跨启动不变，所以用 FNV-1a，不能用每个进程都不同的 hashValue
    private func fileURL(_ key: String) -> URL {
        let hash = key.utf8.reduce(0xcbf2_9ce4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".png")
    }

    /// 全屏等情况下菜单栏不显示，这时同一位置截到的是窗口内容，不能当成图标存下来
    private static var isMenuBarHiddenBySystem: Bool {
        !NSApp.currentSystemPresentationOptions.isDisjoint(with: [.hideMenuBar, .autoHideMenuBar, .fullScreen])
    }

    /// 刘海屏上被刘海挡住的位置截不到图标，跳过
    private static func isActuallyVisible(_ item: MenuBarItem) -> Bool {
        guard let screen = NSScreen.screens.first(where: { CGDisplayBounds(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0).intersects(item.frame) }) else { return false }
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return true }
        let x0 = item.frame.minX - screen.frame.minX, x1 = item.frame.maxX - screen.frame.minX
        return (x1 <= left.maxX) || (x0 >= right.minX)
    }

    /// Window Server 画的那条菜单栏。单独截它，才不会把后面的壁纸拍进来。
    private static func menuBarWindow(in windows: [SCWindow], display bounds: CGRect) -> SCWindow? {
        windows.min { a, b in
            score(a, display: bounds) < score(b, display: bounds)
        }.flatMap { score($0, display: bounds) < 20 ? $0 : nil }
    }

    /// 越小越像菜单栏窗口。差太远就当成没找到。
    private static func score(_ window: SCWindow, display bounds: CGRect) -> CGFloat {
        let f = window.frame
        guard f.height >= 18, f.height <= 80, f.width > bounds.width * 0.5 else { return 100 }
        let dx = abs(f.minX - bounds.minX) + abs(f.width - bounds.width)
        let top = abs(f.minY - bounds.minY)
        let title = window.title ?? ""
        let named: CGFloat = title == "Menubar" || title == "Menu Bar" ? 0 : 4
        return dx + top + named
    }

    /// 截菜单栏。window 不为空时只截这个窗口；否则截显示器上 strip 那一条。
    private static func screenshot(of window: SCWindow?, display: SCDisplay, strip: CGRect, scale: CGFloat) async -> CGImage? {
        let frame = window?.frame ?? strip
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.capturesAudio = false
        config.captureResolution = .nominal
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if #available(macOS 15.0, *) { config.captureDynamicRange = .SDR }
        config.colorSpaceName = CGColorSpace.sRGB
        // 透明部分垫中灰。纯白会吃掉浅色图标，纯黑会吃掉深色图标。
        config.backgroundColor = Self.captureBackground
        config.scalesToFit = true
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
        if window == nil { config.sourceRect = strip }
        config.ignoreShadowsSingleWindow = true
        config.ignoreShadowsDisplay = true
        let filter = window.map { SCContentFilter(desktopIndependentWindow: $0) }
            ?? SCContentFilter(display: display, excludingWindows: [])
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// 上下两条边的亮度离中位数有多远。壁纸透进来时这条边是花的。
    private static func borderSpread(_ image: CGImage) -> Double {
        let w = image.width, h = image.height
        guard w > 4, h > 4,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return 1 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var luma: [Double] = []
        luma.reserveCapacity(w)
        for y in [0, h - 1] {
            for x in stride(from: 0, to: w, by: 2) {
                let i = (y * w + x) * 4
                luma.append((Double(data[i]) + Double(data[i + 1]) + Double(data[i + 2])) / (3 * 255))
            }
        }
        luma.sort()
        let mid = luma[luma.count / 2]
        return luma.map { abs($0 - mid) }.sorted()[luma.count / 2]
    }

    /// 菜单栏放不下时，系统会把多出的图标叠放在自带的「«」按钮下面——这些坐标处截到的并不是它们自己
    private static func isStacked(_ item: MenuBarItem, among items: [MenuBarItem]) -> Bool {
        items.contains { other in
            guard other.key != item.key else { return false }
            let overlap = item.frame.intersection(other.frame).width
            return overlap > min(item.frame.width, other.frame.width) * 0.3
        }
    }

    private static func makeImage(_ rep: NSBitmapImageRep, pointSize: NSSize, template: Bool) -> NSImage {
        rep.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        image.isTemplate = template
        return image
    }

    /// 以图标四周边缘的颜色作为背景，把每个像素反推成「前景色 + 透明度」：
    /// 近乎单色的图标转为模板图（跟随系统深浅色），彩色图标保留原色。
    nonisolated private static func removeBackground(_ image: CGImage) -> (NSBitmapImageRep, Bool)? {
        let w = image.width, h = image.height
        guard w > 2, h > 2,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32),
              let data = rep.bitmapData else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        func px(_ x: Int, _ y: Int) -> (Double, Double, Double) {
            let i = (y * w + x) * 4
            return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
        }
        // 背景：边框像素各通道的中位数
        var border: [(Double, Double, Double)] = []
        for x in 0..<w { border.append(px(x, 0)); border.append(px(x, h - 1)) }
        for y in 0..<h { border.append(px(0, y)); border.append(px(w - 1, y)) }
        func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
        let bg = (median(border.map(\.0)), median(border.map(\.1)), median(border.map(\.2)))

        var saturated = 0, opaque = 0
        for y in 0..<h {
            for x in 0..<w {
                let p = px(x, y)
                func needed(_ c: Double, _ b: Double) -> Double {
                    c < b ? (b - c) / max(b, 0.001) : (c - b) / max(1 - b, 0.001)
                }
                var a = max(needed(p.0, bg.0), needed(p.1, bg.1), needed(p.2, bg.2))
                a = a < 0.06 ? 0 : min(1, a)
                let i = (y * w + x) * 4
                if a == 0 {
                    data[i] = 0; data[i + 1] = 0; data[i + 2] = 0; data[i + 3] = 0
                    continue
                }
                let f = (bg.0 + (p.0 - bg.0) / a, bg.1 + (p.1 - bg.1) / a, bg.2 + (p.2 - bg.2) / a)
                let hi = max(f.0, f.1, f.2), lo = min(f.0, f.1, f.2)
                if a > 0.5 { opaque += 1; if hi - lo > 0.25 { saturated += 1 } }
                // 预乘透明度写回
                data[i] = UInt8(max(0, min(1, f.0)) * a * 255)
                data[i + 1] = UInt8(max(0, min(1, f.1)) * a * 255)
                data[i + 2] = UInt8(max(0, min(1, f.2)) * a * 255)
                data[i + 3] = UInt8(a * 255)
            }
        }
        guard opaque > 0 else { return nil }
        // 有颜色的像素不到 15%：当作单色系统风格图标
        let template = Double(saturated) / Double(opaque) < 0.15

        // 裁掉四周透明边，托盘里排得更紧凑
        var minX = w, maxX = -1
        for y in 0..<h { for x in 0..<w where data[(y * w + x) * 4 + 3] > 25 { minX = min(minX, x); maxX = max(maxX, x) } }
        guard maxX >= minX, let cg = rep.cgImage else { return (rep, template) }
        let pad = 2
        let cropRect = CGRect(x: max(0, minX - pad), y: 0, width: min(w, maxX + pad + 1) - max(0, minX - pad), height: h)
        guard let cropped = cg.cropping(to: cropRect) else { return (rep, template) }
        return (NSBitmapImageRep(cgImage: cropped), template)
    }
}

/// 盖住菜单栏后面那一层，让毛玻璃只模糊到纯色，截出来的图标才没有壁纸残影。
@MainActor
private final class MenuBarBackdrop {
    private var windows: [NSWindow] = []

    func show() {
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        for screen in NSScreen.screens {
            let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            let height = bar + 8
            let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - height, width: screen.frame.width, height: height)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = level
            window.isOpaque = true
            window.backgroundColor = NSColor(white: 0.5, alpha: 1)
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self == 0 ? nil : self }
}
