import AppKit

/// 收进 Veil 的图标：点 Veil 时弹出的就是这一组。
/// 菜单栏本身原样不动，这里只记录「想从 Veil 里取用哪些图标」以及它们的顺序。
enum VeilCollection {
    static let didChange = Notification.Name("VeilCollectionDidChange")
    private static let key = "collectionKeys"

    static var keys: [String] {
        get { UserDefaults.standard.stringArray(forKey: key) ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func contains(_ item: MenuBarItem) -> Bool { keys.contains(item.key) }

    static func add(_ item: MenuBarItem, at index: Int? = nil) {
        var k = keys
        let old = k.firstIndex(of: item.key)
        if let old { k.remove(at: old) }
        var i = index ?? k.count
        if let old, old < i { i -= 1 }
        k.insert(item.key, at: min(max(i, 0), k.count))
        keys = k
    }

    static func remove(_ item: MenuBarItem) {
        keys = keys.filter { $0 != item.key }
    }

    /// 收藏涉及的应用，打开托盘时只需要扫描它们
    static var owners: Set<String> { Set(keys.map(MenuBarItem.owner(ofKey:))) }

    /// 按收藏顺序取出当前正在运行的那些图标
    static func items(from all: [MenuBarItem]) -> [MenuBarItem] {
        entries(from: all).filter { !$0.isMissing }
    }

    /// 按收藏顺序取出全部条目，不在菜单栏上的用占位条目代替（设置页里仍要能看到、移除、排序）
    static func entries(from all: [MenuBarItem]) -> [MenuBarItem] {
        let stored = relinkRenamed(keys, in: all)
        let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return stored.map { byKey[$0] ?? MenuBarItem(missingKey: $0) }
    }

    /// 收藏所属的应用里有没有正在运行的
    static var hasRunningOwner: Bool {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier ?? $0.localizedName }
        return !owners.isDisjoint(with: running)
    }

    /// 有些图标的标题带状态（「某某 · 服务运行中」），状态一变键就变，收藏会悄悄消失。
    /// 应用只有一个图标、且没被别的收藏占用时，可以确定是同一个，把键改过来。
    /// 这里直接写入不发通知：调用方正在用这份结果刷新界面。
    private static func relinkRenamed(_ stored: [String], in all: [MenuBarItem]) -> [String] {
        let current = Set(all.map(\.key))
        var claimed = Set(stored).intersection(current)
        var result = stored
        for (i, old) in stored.enumerated() where !current.contains(old) {
            let owner = MenuBarItem.owner(ofKey: old)
            let sameApp = all.filter { MenuBarItem.owner(ofKey: $0.key) == owner }
            guard sameApp.count == 1, claimed.insert(sameApp[0].key).inserted else { continue }
            result[i] = sameApp[0].key
        }
        if result != stored { UserDefaults.standard.set(result, forKey: key) }
        return result
    }
}
