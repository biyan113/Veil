import AppKit

/// 开发自检：VEIL_SNAPSHOT=<目录> 启动时，把各设置面板渲染为 PNG 后退出
@MainActor
enum DebugSnapshot {
    static func runIfRequested(settings: SettingsWindowController?) {
        guard let dir = ProcessInfo.processInfo.environment["VEIL_SNAPSHOT"],
              let window = settings?.window,
              let tabs = window.contentViewController as? NSTabViewController else { return }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            for i in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = i
                try? await Task.sleep(for: .milliseconds(2500))
                guard let view = window.contentView?.superview else { continue }
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/pane\(i).png"))
            }
            NSApp.terminate(nil)
        }
    }
}
