import AppKit
import ApplicationServices
import PerryCore

/// Finds Dock tiles via the Accessibility API. The only macOS permission Perry ever asks for;
/// everything degrades gracefully without it.
enum DockIcon {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "Perry would like to control this computer" prompt (once per grant state).
    static func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// Horizontal centre (global points) of the first Dock tile whose title matches. x is valid
    /// even while the Dock is hidden — it slides straight down, so tiles keep their x.
    static func centerX(where matches: (String) -> Bool) -> CGFloat? {
        guard trusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let item = find(in: app, depth: 3, matches) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        guard let p = attr(item, kAXPositionAttribute), let s = attr(item, kAXSizeAttribute),
              AXValueGetValue(p as! AXValue, .cgPoint, &pos),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        dlog("dock tile \(attr(item, kAXTitleAttribute) as? String ?? "?") at x=\(Int(pos.x)) w=\(Int(size.width))")
        return pos.x + size.width / 2
    }

    private static func find(in el: AXUIElement, depth: Int, _ matches: (String) -> Bool) -> AXUIElement? {
        for child in (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let t = attr(child, kAXTitleAttribute) as? String, matches(t) { return child }
            if depth > 0, let hit = find(in: child, depth: depth - 1, matches) { return hit }
        }
        return nil
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}
