import AppKit
import QuartzCore
import PerryCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: OverlayWindow!
    private var view: PerryView!
    private var brain: Brain!
    private var spriteSize = CGSize(width: Config.spriteHeight, height: Config.spriteHeight)
    private var animator: Animator!
    private var frames: [String: [NSImage]] = [:]
    private var server: ControlServer?
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var alertTargetX: CGFloat?
    private var alertSource = "-"

    func applicationDidFinishLaunching(_ note: Notification) {
        frames = SpriteLoader.load()
        animator = Animator(counts: frames.mapValues { $0.count }, fps: Config.fps, oneShot: Config.oneShot, holds: Config.holds)
        brain = Brain(hasWake: !(frames["wake"] ?? []).isEmpty)
        if let f = frames["walk"]?.first, f.size.height > 0 {
            spriteSize = CGSize(width: Config.spriteHeight * f.size.width / f.size.height, height: Config.spriteHeight)
        }
        let screen = ScreenInfo.primary
        window = OverlayWindow(screen: screen)
        view = PerryView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.spriteSize = spriteSize
        window.contentView = view
        brain.onStateChange = { [weak self] from, to in self?.stateChanged(from, to) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.window.fit(to: ScreenInfo.primary)
        }
        startServer()
        dlog("ready, state=\(brain.state.rawValue), screen=\(screen.frame), ground=\(ScreenInfo.targetGroundY(screen)) dockShown=\(ScreenInfo.dockShown())")
    }

    // MARK: server

    private func startServer() {
        let die: (String) -> Void = { msg in
            FileHandle.standardError.write(Data("Perry: \(msg)\n".utf8)); exit(1)
        }
        do {
            let s = try ControlServer(port: Config.port) { [weak self] req in
                guard let self else { return (500, "{}") }
                return DispatchQueue.main.sync { self.route(req) }
            }
            s.start { err in die("cannot listen on 127.0.0.1:\(Config.port) — already running? (\(err))") }
            server = s
        } catch {
            die("cannot create listener: \(error)")
        }
    }

    private func route(_ r: HTTPRequest) -> (Int, String) {
        let now = Date().timeIntervalSince1970
        dlog("\(r.method) \(r.path) session=\(r.sessionID)")
        switch (r.method, r.path) {
        case ("POST", "/start"):    brain.start(session: r.sessionID, now: now)
        case ("POST", "/complete"): brain.complete(session: r.sessionID, now: now)
        case ("POST", "/end"):      brain.end(session: r.sessionID, now: now)
        case ("POST", "/hide"):     brain.hide()
        case ("POST", "/quit"):     DispatchQueue.main.async { NSApp.terminate(nil) }
        case ("GET", "/ping"):      break
        case ("POST", "/ax"):       DockIcon.requestAccess()
        default: return (404, #"{"error":"not found"}"#)
        }
        return (200, #"{"state":"\#(brain.state.rawValue)","working":\#(brain.working.count),"open":\#(brain.open.count),"accessibility":\#(DockIcon.trusted),"target":\#(alertTargetX.map { "\(Int($0))" } ?? "null"),"targetSource":"\#(alertSource)"}"#)
    }

    // MARK: state → window/timer

    private func stateChanged(_ from: PetState, _ to: PetState) {
        if to == .alert {
            let t = ScreenInfo.alertTarget()
            alertTargetX = t.x
            alertSource = t.source
            dlog("alert target: \(t.source)\(t.x.map { " x=\(Int($0))" } ?? "")")
        }
        if to == .hidden {
            stopTimer()
            window.orderOut(nil)
            return
        }
        if from == .hidden {
            window.fit(to: ScreenInfo.primary)
            view.groundY = ScreenInfo.targetGroundY(ScreenInfo.primary)   // no slide-in on first show
            window.alphaValue = 0
            window.orderFrontRegardless()
            fadeIn()
            startTimer()
            return
        }
        // .buried: the dig-and-vanish easter egg. Same on/off-screen handling as hidden, but the
        // tick loop keeps running so the buried countdown (and a real bark, if one interrupts it) still ticks.
        if to == .buried {
            window.orderOut(nil)
        } else if from == .buried {
            window.alphaValue = 0
            window.orderFrontRegardless()
            fadeIn()
        }
    }

    private func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            self.window.animator().alphaValue = 1
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        last = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate(); timer = nil
    }

    private func tick() {
        let t = CACurrentMediaTime()
        let dt = min(t - last, 0.1); last = t
        let screen = ScreenInfo.primary
        let half = spriteSize.width / 2
        let env = Env(minX: screen.frame.minX + Config.edgeMargin + half,
                      maxX: screen.frame.maxX - Config.edgeMargin - half,
                      vsCodeCenterX: alertTargetX,
                      now: Date().timeIntervalSince1970)
        brain.tick(dt: dt, env: env)
        animator.set(brain.animation)
        let idx = animator.tick(dt: dt)
        // A character can skip any easter-egg role's art entirely (no zoomies/dig/etc. folder);
        // fall back to idle rather than flash the magenta "missing" rectangle.
        let list = frames[brain.animation].flatMap { $0.isEmpty ? nil : $0 } ?? frames["idle"] ?? []
        view.image = list.indices.contains(idx) ? list[idx] : nil
        view.x = brain.x - screen.frame.minX
        let ground = ScreenInfo.targetGroundY(screen)          // rides the Dock as it slides
        if abs(ground - view.groundY) < 0.5 { view.groundY = ground }
        else { view.groundY += (ground - view.groundY) * min(1, 14 * CGFloat(dt)) }
        view.facingRight = brain.facingRight
        view.needsDisplay = true
    }
}
