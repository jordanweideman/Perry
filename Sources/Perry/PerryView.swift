import AppKit
import PerryCore

/// Draws one sprite frame with feet at `groundY`, centred on `x` (window coordinates).
final class PerryView: NSView {
    var image: NSImage?
    var x: CGFloat = 0
    var groundY: CGFloat = 0
    var facingRight = true
    var spriteSize = CGSize(width: Config.spriteHeight, height: Config.spriteHeight)

    override func draw(_ dirtyRect: NSRect) {
        let s = spriteSize
        let rect = NSRect(x: x - s.width / 2, y: groundY, width: s.width, height: s.height)
        guard let img = image else {
            NSColor.magenta.setFill(); rect.fill()          // no sprites found
            return
        }
        NSGraphicsContext.current?.imageInterpolation = .high
        if facingRight {
            img.draw(in: rect)
        } else {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: rect.midX * 2, yBy: 0)
            t.scaleX(by: -1, yBy: 1)
            t.concat()
            img.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
