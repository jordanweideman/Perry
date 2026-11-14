import Foundation
import PerryCore

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "  ok    " : "  FAIL  ") + msg)
    if !cond { failures += 1 }
}

// Animator: 6 walk frames at 10 fps
let anim = Animator(counts: ["walk": 6], fps: ["walk": 10], initial: "walk")
check(anim.tick(dt: 0.15) == 1, "animator advances one frame after 0.15s")
check(anim.tick(dt: 0.50) == 0, "animator wraps after a full cycle")
let once = Animator(counts: ["wake": 3], fps: ["wake": 4], oneShot: ["wake"], initial: "wake")
check(once.tick(dt: 2.0) == 2, "one-shot animation holds its last frame")
let held = Animator(counts: ["alert": 4], fps: ["alert": 5], holds: ["alert": [4, 1, 1, 3]], initial: "alert")
check(held.tick(dt: 0.75) == 0, "held frame 0 lasts 4 ticks (0.8s)")
check(held.tick(dt: 0.10) == 1, "then advances")
check(held.tick(dt: 0.20) == 2 && held.tick(dt: 0.20) == 3, "unheld frames last 1 tick")
check(held.tick(dt: 0.50) == 3 && held.tick(dt: 0.10) == 0, "last frame held 3 ticks, then loops")

// Sessions
let st = SessionTracker()
st.touch("a", now: 0); st.touch("b", now: 0)
check(!st.sweep(now: 100, staleAfter: 300), "sweep keeps fresh sessions")
check(st.sweep(now: 400, staleAfter: 300) && st.isEmpty, "sweep expires stale sessions and reports emptied")

// Brain: events + multi-session rules
func env(now: TimeInterval, vs: CGFloat? = nil) -> Env { Env(minX: 100, maxX: 1000, vsCodeCenterX: vs, now: now) }
let b = Brain()
var calls = 0
b.random = { r in
    // Easter-egg cooldown/buried-duration rolls use their own fixed Config ranges; keep them
    // pinned low so arming one (on first appearance) doesn't shift the position/pause parity
    // the rest of this block counts on.
    if r == CGFloat(Config.eggCooldownRange.lowerBound)...CGFloat(Config.eggCooldownRange.upperBound)
        || r == CGFloat(Config.buriedRange.lowerBound)...CGFloat(Config.buriedRange.upperBound) {
        return r.lowerBound
    }
    calls += 1
    return calls % 2 == 1 ? r.lowerBound : r.upperBound
}
check(b.state == .hidden, "starts hidden")
b.start(session: "A", now: 0);            check(b.state == .working, "start -> working")
b.tick(dt: 0.016, env: env(now: 0));      check(b.x == 100, "placed at random x on first working tick")
b.tick(dt: 0.016, env: env(now: 1))       // pause over -> target 1000
b.tick(dt: 1.0, env: env(now: 2))
check(abs(b.x - (100 + Config.walkSpeed)) < 0.001 && b.facingRight && b.animation == "walk", "walks toward target at walkSpeed, facing right")
b.start(session: "B", now: 2)
b.complete(session: "A", now: 3);         check(b.state == .alert, "any session completing -> alert")
b.start(session: "B", now: 3);            check(b.state == .alert, "heartbeat/start during alert does not interrupt the wave")
b.tick(dt: 10, env: env(now: 3, vs: 200)); check(b.x == 200 && b.animation == "alert", "walks to VS Code and plays alert (wave/bark)")
b.tick(dt: 0.016, env: env(now: 3 + Config.waveDuration + 0.1, vs: 200))
check(b.state == .working, "wave over, B still working -> resumes wandering")
b.complete(session: "B", now: 10);        check(b.state == .alert, "last session completing -> alert")
b.tick(dt: 10, env: env(now: 10, vs: 200))
b.tick(dt: 0.016, env: env(now: 10 + Config.waveDuration + 0.1, vs: 200))
check(b.state == .alertIdle && b.animation == "sleep", "wave over, nothing working -> sleeps")
b.end(session: "A", now: 20);             check(b.state == .alertIdle, "one session closed, another open -> stays")
b.end(session: "B", now: 20);             check(b.state == .hidden, "all sessions closed -> hidden")
b.complete(session: "Z", now: 21);        check(b.state == .alert, "completion from an unseen session (Perry launched late) -> still waves")

// Brain: wake-up stretch between sleep and walk (characters with a wake animation)
let w = Brain(hasWake: true)
w.start(session: "S", now: 0); w.tick(dt: 0.016, env: env(now: 0))
w.complete(session: "S", now: 1); w.tick(dt: 30, env: env(now: 1, vs: 200))   // dt big enough to arrive from any x
w.tick(dt: 0.016, env: env(now: 1 + Config.waveDuration + 0.1, vs: 200)); check(w.state == .alertIdle, "asleep")
w.start(session: "S2", now: 10);          check(w.state == .waking && w.animation == "wake", "start while asleep -> waking (stretch)")
w.tick(dt: 0.016, env: env(now: 10.5));   check(w.state == .waking, "still stretching before wakeDuration")
w.tick(dt: 0.016, env: env(now: 10 + Config.wakeDuration + 0.1)); check(w.state == .working, "after stretch -> working")
let nw = Brain(hasWake: false)
nw.start(session: "S", now: 0); nw.tick(dt: 0.016, env: env(now: 0)); nw.complete(session: "S", now: 1); nw.tick(dt: 30, env: env(now: 1, vs: 200))
nw.tick(dt: 0.016, env: env(now: 1 + Config.waveDuration + 0.1, vs: 200)); nw.start(session: "S2", now: 10)
check(nw.state == .working, "character without wake animation skips straight to working")

// Brain: stale sessions
let c = Brain()
c.start(session: "A", now: 0); c.tick(dt: 0.016, env: env(now: 0))
c.tick(dt: 0.016, env: env(now: 400));    check(c.state == .alertIdle, "turn silent 5min -> stands idle (no false wave, not hidden)")
c.tick(dt: 0.016, env: env(now: 2000));   check(c.state == .hidden, "session silent 30min -> hidden")

// Brain: alert walking direction
let a = Brain()
a.start(session: "S", now: 0); a.tick(dt: 0.016, env: env(now: 0)); a.x = 500
a.complete(session: "S", now: 1)
a.tick(dt: 1.0, env: env(now: 1, vs: 400))
check(abs(a.x - (500 - Config.walkSpeed)) < 0.001 && !a.facingRight && a.animation == "walk", "alert walks toward VS Code, facing left")

// Brain: easter eggs — rare, and only ever entered/left from .working.
// `start(session:, now:)` doubles as the heartbeat: called again with the same session it just
// touches the trackers (no transition, since state is already .working), keeping the session out
// of staleAfter's reach right up to the moment each test rolls forward.
let eggA = Brain()
eggA.random = { r in r.lowerBound }   // cooldown -> 900 (lowerBound); kind index 0 -> zoomies
eggA.start(session: "S", now: 0)
eggA.start(session: "S", now: 900)
eggA.tick(dt: 0.016, env: env(now: 901))
check(eggA.state == .zoomies, "cooldown elapsed at a wander decision -> rolls an egg (index 0 -> zoomies)")
eggA.tick(dt: Config.zoomiesDuration + 0.1, env: env(now: 901 + Config.zoomiesDuration + 0.1))
check(eggA.state == .working, "zoomies duration elapsed -> resumes ordinary working")

let eggB = Brain()
var eggBPosCalls = 0
eggB.random = { r in
    if r == 0...4 { return 2 }                                                                  // kind index 2 -> digging
    if r == CGFloat(Config.eggCooldownRange.lowerBound)...CGFloat(Config.eggCooldownRange.upperBound) { return r.lowerBound }
    if r == CGFloat(Config.buriedRange.lowerBound)...CGFloat(Config.buriedRange.upperBound) { return r.lowerBound }
    eggBPosCalls += 1
    return eggBPosCalls == 1 ? r.lowerBound : r.upperBound   // first placement, then the buried-exit reposition
}
eggB.start(session: "S", now: 0)
eggB.start(session: "S", now: 900)
eggB.tick(dt: 0.016, env: env(now: 901))
check(eggB.state == .digging, "kind index 2 -> digging")
eggB.tick(dt: Config.diggingDuration + 0.1, env: env(now: 901 + Config.diggingDuration + 0.1))
check(eggB.state == .buried, "dig finishes -> buried (window hidden by AppDelegate, brain keeps ticking)")
let buriedEnd = 901 + Config.diggingDuration + 0.1 + Config.buriedRange.lowerBound + 0.1
eggB.tick(dt: Config.buriedRange.lowerBound + 0.1, env: env(now: buriedEnd))
check(eggB.state == .poppingUp && eggB.x == 1000, "buried timer elapses -> pops up, repositioned along the Dock")
eggB.tick(dt: Config.poppingUpDuration + 0.1, env: env(now: buriedEnd + Config.poppingUpDuration + 0.1))
check(eggB.state == .working, "pop-up finishes -> resumes working, cooldown re-armed")
eggB.tick(dt: 0.1, env: env(now: buriedEnd + Config.poppingUpDuration + 1))
check(eggB.state == .working, "cooldown re-armed far in the future -> no back-to-back egg")

let eggC = Brain()
eggC.random = { r in r.lowerBound }
eggC.start(session: "S", now: 0)
eggC.start(session: "S", now: 900)
eggC.tick(dt: 0.016, env: env(now: 901))
check(eggC.state == .zoomies, "egg rolling as expected before the interrupt check")
eggC.complete(session: "S", now: 901.5)
check(eggC.state == .alert, "a real turn completing always interrupts an easter egg in progress")

let eggD = Brain()
eggD.random = { r in r.lowerBound }
eggD.start(session: "S", now: 0)
eggD.start(session: "S", now: 900)
eggD.tick(dt: 0.016, env: env(now: 901))
check(eggD.state == .zoomies, "egg rolling as expected before the staleness check")
eggD.tick(dt: 0.016, env: env(now: 901 + Config.staleAfter + 31))
check(eggD.state == .alertIdle, "sessions going stale mid-egg still safely fall back to idle, not stuck")

let eggE = Brain()
eggE.random = { r in r.upperBound }   // kind index: Int(4.0) clamped to the last kind (carrying), not a crash
eggE.start(session: "S", now: 0)
eggE.start(session: "S", now: 1800)
eggE.tick(dt: 0.016, env: env(now: 1801))
check(eggE.state == .carrying, "random landing exactly on the upper bound clamps to the last egg kind")

// HTTP
let raw = Data("POST /start HTTP/1.1\r\nHost: x\r\nContent-Length: 20\r\n\r\n{\"session_id\":\"abc\"}".utf8)
let req = HTTPRequest.parse(raw)
check(req?.path == "/start" && req?.method == "POST", "parses request line")
check(req?.sessionID == "abc", "extracts session_id")
check(HTTPRequest.parse(Data("GET /ping HTTP/1.1\r\n\r\n".utf8))?.sessionID == "manual", "no body -> manual")
check(HTTPRequest.parse(Data("POST /x HTTP/1.1\r\nContent-Length: 50\r\n\r\n{".utf8)) == nil, "incomplete body -> nil")

print(failures == 0 ? "ALL PASS" : "\(failures) FAILURE(S)")
exit(failures == 0 ? 0 : 1)
