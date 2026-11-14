import Foundation

/// Steps through frame indices for the current animation at its configured FPS. Always loops.
public final class Animator {
    public private(set) var name: String
    public private(set) var index = 0
    private var acc: TimeInterval = 0
    private let counts: [String: Int]
    private let fps: [String: Double]
    private let oneShot: Set<String>
    private let holds: [String: [Int]]

    public init(counts: [String: Int], fps: [String: Double], oneShot: Set<String> = [],
                holds: [String: [Int]] = [:], initial: String = "idle") {
        self.counts = counts; self.fps = fps; self.oneShot = oneShot; self.holds = holds; self.name = initial
    }

    private func duration(of frame: Int) -> TimeInterval {
        let h = holds[name].flatMap { frame < $0.count ? $0[frame] : nil } ?? 1
        return Double(max(h, 1)) / (fps[name] ?? 8)
    }

    public func set(_ n: String) {
        guard n != name else { return }
        name = n; index = 0; acc = 0
    }

    @discardableResult
    public func tick(dt: TimeInterval) -> Int {
        let n = max(counts[name] ?? 1, 1)
        acc += dt
        while acc >= duration(of: index) {
            acc -= duration(of: index)
            if index + 1 < n { index += 1 } else if !oneShot.contains(name) { index = 0 }
        }
        return index
    }
}
