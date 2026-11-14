import AppKit
import QuartzCore
import PerryCore

enum ScreenInfo {
    static var primary: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    /// Where Perry's feet should be right now (window-local points): on top of the Dock while
    /// it's showing, on the screen's bottom edge while it's hidden.
    static func targetGroundY(_ s: NSScreen) -> CGFloat {
        (dockShown() ? dockHeight(s) : Config.dockHiddenGround) + Config.groundOffset
    }

    private static var dockShownCached = true
    private static var dockCheckedAt: TimeInterval = 0

    /// The Dock's layer-20 window leaves the on-screen list while hidden (fullscreen Spaces,
    /// auto-hide) and returns while it's raised. Polled at 10Hz; no permissions needed.
    static func dockShown() -> Bool {
        let now = CACurrentMediaTime()
        guard now - dockCheckedAt > 0.1 else { return dockShownCached }
        dockCheckedAt = now
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let shown = list.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 20
        }
        if shown != dockShownCached { dlog("dock \(shown ? "shown" : "hidden")") }
        dockShownCached = shown
        return shown
    }

    /// Dock height when showing. visibleFrame reports it unless auto-hide is on system-wide,
    /// then estimate from the tile size (54 → 75 on a standard Dock).
    static func dockHeight(_ s: NSScreen) -> CGFloat {
        let inset = s.visibleFrame.minY - s.frame.minY
        if inset > 0 { return inset }
        let tile = UserDefaults(suiteName: "com.apple.dock")?.double(forKey: "tilesize") ?? 54
        return CGFloat(tile == 0 ? 54 : tile) + 21
    }

    /// Where Perry should wave: the VS Code Dock icon if Accessibility allows, else the VS Code
    /// window, else nil (caller uses screen centre).
    static func alertTarget() -> (x: CGFloat?, source: String) {
        if let x = DockIcon.centerX(where: Config.isVSCodeDockTitle) { return (x, "dock icon (Accessibility)") }
        if let x = Config.vsCodeIconX { return (x, "dock icon (Config.vsCodeIconX)") }
        if let x = vsCodeCenterX() { return (x, "VS Code window") }
        return (nil, "screen centre (VS Code not found)")
    }

    /// Horizontal centre of the largest VS Code window. Prefers windows on the current Space.
    /// Needs no Accessibility or Screen Recording permission.
    static func vsCodeCenterX() -> CGFloat? {
        largestVSCodeWindow(.optionOnScreenOnly)?.midX ?? largestVSCodeWindow(.optionAll)?.midX
    }

    private static func largestVSCodeWindow(_ opt: CGWindowListOption) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([opt, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        var best: CGRect?
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String,
                  Config.vsCodeOwnerNames.contains(owner),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict),
                  r.width > 200, r.height > 200 else { continue }
            if best == nil || r.width * r.height > best!.width * best!.height { best = r }
        }
        if let b = best { dlog("vscode window \(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height))") }
        return best
    }
}
