import Foundation
import CoreGraphics

/// Every tunable in one place.
public enum Config {
    public static let port: UInt16 = 7717
    /// Which folder under Sprites/ to use. Each character has the same animation *roles*:
    /// idle, walk, sleep, alert (wave / bark), and optionally wake (played once when leaving sleep).
    public static let character = "dog"
    public static let spriteHeight: CGFloat = 60                    // points on screen; width follows the frame aspect
    public static let windowHeight: CGFloat = 200                   // overlay strip height
    public static let groundOffset: CGFloat = 0                     // nudge feet up/down (all cases)
    public static let dockHiddenGround: CGFloat = 0                 // feet height while the Dock is hidden
    public static let edgeMargin: CGFloat = 40                      // keep away from screen edges
    public static let walkSpeed: CGFloat = 55                       // points per second
    public static let pauseRange: ClosedRange<Double> = 1.0...3.0   // seconds between wanders
    public static let waveDuration: TimeInterval = 5.5             // how long the alert (bark/wave) plays
    public static let staleAfter: TimeInterval = 300                // a turn silent this long is no longer 'working'
    public static let openStaleAfter: TimeInterval = 1800           // a session silent this long is treated as closed
    public static let fps: [String: Double] = ["idle": 4, "walk": 8, "alert": 5, "sleep": 3, "wake": 4,
                                                "zoomies": 12, "chasetail": 6, "dig": 4, "popup": 4, "carry": 8]
    /// Per-frame hold multipliers (frame N lasts holds[N] ticks). Bark: look… bark, bark… howl…
    public static let holds: [String: [Int]] = ["alert": [4, 1, 1, 3]]
    public static let oneShot: Set<String> = ["wake", "dig", "popup"]   // play once, hold the last frame
    public static let wakeDuration: TimeInterval = 1.5              // sleep → stretch → walk

    // MARK: easter eggs — very occasional detours from ordinary wandering, never during a bark or sleep.
    /// How long between eggs: a fresh random gap in this range is picked after Perry appears and after
    /// every egg finishes, so they land on no predictable clock.
    public static let eggCooldownRange: ClosedRange<TimeInterval> = 900...1800   // 15–30 min
    public static let zoomiesDuration: TimeInterval = 3.0
    public static let zoomiesSpeed: CGFloat = 170                    // a fast dash, well above walkSpeed
    public static let chaseTailDuration: TimeInterval = 2.5
    public static let carryDuration: TimeInterval = 6.0              // trots around holding a toy
    public static let diggingDuration: TimeInterval = 1.4            // plays the dig-in animation, then vanishes
    public static let buriedRange: ClosedRange<TimeInterval> = 5...15  // how long he's gone before popping up
    public static let poppingUpDuration: TimeInterval = 1.2
    public static let vsCodeOwnerNames: Set<String> = ["Code", "Code - Insiders"]
    /// Where Perry waves: the centre of the VS Code icon in the Dock, in points from the left of the
    /// screen. Measured from a screenshot: (pixel x ÷ 2 on a retina display). nil → use the VS Code
    /// window instead. Only overridden if the Accessibility permission was granted via `./perry ax`.
    public static let vsCodeIconX: CGFloat? = 1106   // 15" MacBook Air, 1710pt wide
    /// Dock tile titles are the app's display name.
    public static func isVSCodeDockTitle(_ t: String) -> Bool { t == "Code" || t.hasPrefix("Visual Studio Code") }
    public static let debug = ProcessInfo.processInfo.environment["PERRY_DEBUG"] == "1"
}

public func dlog(_ msg: @autoclosure () -> String) {
    guard Config.debug else { return }
    FileHandle.standardError.write(Data(("[perry] " + msg() + "\n").utf8))
}
