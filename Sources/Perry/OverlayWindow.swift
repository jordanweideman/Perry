import AppKit
import PerryCore

/// Transparent strip along the bottom of the primary screen. Never moves, never takes focus,
/// follows the user into every Space including other apps' fullscreen.
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        let f = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                       width: screen.frame.width, height: Config.windowHeight)
        super.init(contentRect: f, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
    /// Re-pin to the screen's bottom edge (screen size / resolution may have changed since launch).
    func fit(to screen: NSScreen) {
        let f = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                       width: screen.frame.width, height: Config.windowHeight)
        if frame != f { setFrame(f, display: true); dlog("overlay refit \(f)") }
    }
    /// AppKit otherwise shoves a window overlapping the Dock up into visibleFrame, which lifts
    /// Perry a whole Dock-height too high.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
