import Foundation
import CoreGraphics

public enum PetState: String {
    case hidden, working, alert, alertIdle, waking
    // Easter eggs — rare detours out of .working, always back to .working when done.
    case zoomies, chaseTail, digging, buried, poppingUp, carrying
}

/// What the brain needs from the outside world each tick.
public struct Env {
    public var minX: CGFloat          // walkable range for Perry's centre
    public var maxX: CGFloat
    public var vsCodeCenterX: CGFloat?
    public var now: TimeInterval
    public init(minX: CGFloat, maxX: CGFloat, vsCodeCenterX: CGFloat?, now: TimeInterval) {
        self.minX = minX; self.maxX = maxX; self.vsCodeCenterX = vsCodeCenterX; self.now = now
    }
}

/// State machine + movement. Pure: no AppKit, no timers.
public final class Brain {
    public private(set) var state: PetState = .hidden
    public var x: CGFloat = 0
    public private(set) var facingRight = true
    public private(set) var animation = "idle"
    /// Sessions mid-turn (start → complete). After a wave, non-empty ⇒ resume wandering.
    public let working = SessionTracker()
    /// Sessions whose Claude Code is still open (any event → SessionEnd). Empty ⇒ Perry hides.
    public let open = SessionTracker()
    public var random: (ClosedRange<CGFloat>) -> CGFloat = { CGFloat.random(in: $0) }
    public var onStateChange: ((PetState, PetState) -> Void)?

    private var placed = false
    private var target: CGFloat?
    private var pauseUntil: TimeInterval = 0
    private var alertTarget: CGFloat?
    private var waveUntil: TimeInterval?
    private var lastSweep: TimeInterval = 0
    private var wakeUntil: TimeInterval = 0
    private let hasWake: Bool
    /// When the next easter egg is allowed to fire. Armed on first appearance and after each egg.
    private var nextEggAt: TimeInterval = .infinity
    /// Generic "this egg step ends at" timer, reused by every egg state.
    private var eggUntil: TimeInterval = 0
    /// Zoomies' own wander target (kept separate from `target` so a mid-egg interruption can't
    /// leave a stray fast-travel target lying around for ordinary wandering to pick up).
    private var eggTarget: CGFloat?

    /// `hasWake`: the character has a wake animation, so leaving sleep goes via .waking.
    public init(hasWake: Bool = false) { self.hasWake = hasWake }

    // MARK: events

    public func start(session: String, now: TimeInterval) {
        open.touch(session, now: now)
        working.touch(session, now: now)
        // During a wave (.alert) or an easter egg, other sessions' heartbeats keep arriving —
        // let it finish; tick() resumes wandering afterwards if anything is still working.
        if state == .hidden {
            nextEggAt = now + eggInterval()
            transition(.working, now: now)
        } else if state == .alertIdle {
            transition(hasWake ? .waking : .working, now: now)
        }
    }

    /// Any session finishing its turn earns a wave.
    public func complete(session: String, now: TimeInterval) {
        open.touch(session, now: now)
        working.remove(session)
        if state == .alert {
            if let until = waveUntil { waveUntil = max(until, now + Config.waveDuration) }  // already waving: hold it
        } else {
            transition(.alert, now: now)   // the real thing always outranks an easter egg in progress
        }
    }

    public func end(session: String, now: TimeInterval) {
        open.remove(session)
        working.remove(session)
        if open.isEmpty { transition(.hidden, now: now) }
    }

    public func hide() {
        open.removeAll(); working.removeAll()
        transition(.hidden, now: 0)
    }

    // MARK: tick

    public func tick(dt: TimeInterval, env: Env) {
        if env.now - lastSweep > 30 {
            lastSweep = env.now
            let workEmptied = working.sweep(now: env.now, staleAfter: Config.staleAfter)
            let openEmptied = open.sweep(now: env.now, staleAfter: Config.openStaleAfter)
            if openEmptied { transition(.hidden, now: env.now); return }
            // lost track of every working session: stand still, no false wave — even mid-egg
            if workEmptied, isWorkingLike(state) { transition(.alertIdle, now: env.now); return }
        }
        switch state {
        case .hidden:
            return
        case .working:
            if !placed { x = random(env.minX...env.maxX); placed = true }
            if let t = target {
                if step(toward: t, dt: dt) {
                    target = nil
                    let r = Config.pauseRange
                    pauseUntil = env.now + Double(random(CGFloat(r.lowerBound)...CGFloat(r.upperBound)))
                    animation = "idle"
                } else {
                    animation = "walk"
                }
            } else if env.now >= pauseUntil {
                if env.now >= nextEggAt {
                    startEasterEgg(now: env.now)
                } else {
                    target = random(env.minX...env.maxX)
                    dlog("wander -> \(Int(target!))")
                }
            }
        case .alert:
            if !placed { x = (env.minX + env.maxX) / 2; placed = true }
            if alertTarget == nil {
                let want = env.vsCodeCenterX ?? (env.minX + env.maxX) / 2
                alertTarget = min(max(want, env.minX), env.maxX)
                dlog("alert target \(Int(alertTarget!)) (vscode: \(env.vsCodeCenterX.map { "\(Int($0))" } ?? "not found"))")
            }
            if step(toward: alertTarget!, dt: dt) {
                if let until = waveUntil {
                    if env.now >= until { transition(working.isEmpty ? .alertIdle : .working, now: env.now) }
                } else {
                    waveUntil = env.now + Config.waveDuration
                    animation = "alert"
                }
            } else {
                animation = "walk"
            }
        case .alertIdle:
            animation = "sleep"
        case .waking:
            if env.now >= wakeUntil { transition(.working, now: env.now) }

        // MARK: easter eggs
        case .zoomies:
            if eggTarget == nil { eggTarget = random(env.minX...env.maxX) }
            if step(toward: eggTarget!, dt: dt, speed: Config.zoomiesSpeed) { eggTarget = nil }
            animation = "zoomies"
            if env.now >= eggUntil { finishEgg(now: env.now) }
        case .chaseTail:
            animation = "chasetail"
            if env.now >= eggUntil { finishEgg(now: env.now) }
        case .carrying:
            if target == nil || step(toward: target!, dt: dt) { target = random(env.minX...env.maxX) }
            animation = "carry"
            if env.now >= eggUntil { finishEgg(now: env.now) }
        case .digging:
            animation = "dig"
            if env.now >= eggUntil { transition(.buried, now: env.now) }
        case .buried:
            if env.now >= eggUntil {
                x = random(env.minX...env.maxX)   // reappear somewhere else along the Dock
                transition(.poppingUp, now: env.now)
            }
        case .poppingUp:
            animation = "popup"
            if env.now >= eggUntil { finishEgg(now: env.now) }
        }
    }

    /// Moves toward `t` at `speed` points/sec; returns true once there.
    private func step(toward t: CGFloat, dt: TimeInterval, speed: CGFloat = Config.walkSpeed) -> Bool {
        let d = t - x
        let len = speed * CGFloat(dt)
        if abs(d) <= len { x = t; return true }
        facingRight = d > 0
        x += d > 0 ? len : -len
        return false
    }

    private func eggInterval() -> TimeInterval {
        let r = Config.eggCooldownRange
        return Double(random(CGFloat(r.lowerBound)...CGFloat(r.upperBound)))
    }

    /// Rolls one of the four eggs and starts it. Only called from .working, between wanders.
    private func startEasterEgg(now: TimeInterval) {
        let kinds: [PetState] = [.zoomies, .chaseTail, .digging, .carrying]
        let idx = min(kinds.count - 1, max(0, Int(random(0...CGFloat(kinds.count)))))
        transition(kinds[idx], now: now)
    }

    /// Ends whichever egg is running, re-arms the cooldown, and resumes ordinary wandering.
    private func finishEgg(now: TimeInterval) {
        nextEggAt = now + eggInterval()
        transition(.working, now: now)
    }

    private func isWorkingLike(_ s: PetState) -> Bool {
        switch s {
        case .working, .zoomies, .chaseTail, .digging, .buried, .poppingUp, .carrying: return true
        case .hidden, .alert, .alertIdle, .waking: return false
        }
    }

    private func transition(_ to: PetState, now: TimeInterval) {
        let from = state
        state = to
        target = nil; alertTarget = nil; waveUntil = nil; eggTarget = nil
        switch to {
        case .hidden:     placed = false; animation = "idle"
        case .working:    pauseUntil = now + 0.5; animation = "idle"
        case .alert:      animation = "walk"
        case .alertIdle:  animation = "sleep"
        case .waking:     wakeUntil = now + Config.wakeDuration; animation = "wake"
        case .zoomies:    eggUntil = now + Config.zoomiesDuration; animation = "zoomies"
        case .chaseTail:  eggUntil = now + Config.chaseTailDuration; animation = "chasetail"
        case .carrying:   eggUntil = now + Config.carryDuration; animation = "carry"
        case .digging:    eggUntil = now + Config.diggingDuration; animation = "dig"
        case .buried:     eggUntil = now + Double(random(CGFloat(Config.buriedRange.lowerBound)...CGFloat(Config.buriedRange.upperBound))); animation = "idle"
        case .poppingUp:  eggUntil = now + Config.poppingUpDuration; animation = "popup"
        }
        dlog("state \(from) -> \(to)")
        onStateChange?(from, to)
    }
}
