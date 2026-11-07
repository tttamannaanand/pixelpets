// Pixel Pets: Thea, Ivan and Kai, living on your screen.
//
// Each pet is a small transparent window that floats above your apps. Pets walk along
// the bottom of the screen and the tops of your windows, jump between them, fall when a
// window moves away, watch your cursor, nap when you're away, and react when you click
// or pick them up. Settings live in the menu bar icon.

import AppKit
import ServiceManagement

// MARK: - Sprites

enum Kind { case cat, dog }

/// Native sprite size, from sprites.py.
let spriteW: CGFloat = 36
let spriteH: CGFloat = 34
let pawGap: CGFloat = 1 // empty rows under the paws
let fxRoom: CGFloat = 14 // extra room above the head for hearts and z's (in sprite pixels)

final class SpriteBook {
    private var cache: [String: CGImage] = [:]
    let root: URL

    init(root: URL) { self.root = root }

    func image(_ pet: String, _ name: String) -> CGImage? {
        let key = "\(pet)/\(name)"
        if let img = cache[key] { return img }
        let url = root.appendingPathComponent(pet).appendingPathComponent("\(name).png")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        cache[key] = img
        return img
    }

    func count(_ pet: String, _ pose: String) -> Int {
        var n = 0
        while image(pet, "\(pose)_\(n)") != nil { n += 1 }
        return n
    }
}

// MARK: - Sounds

@MainActor
final class SoundBank {
    private var sounds: [String: NSSound] = [:]
    var on = true

    init(root: URL) {
        for name in ["hiss", "mew", "boof", "tap"] {
            if let s = NSSound(contentsOf: root.appendingPathComponent("\(name).wav"), byReference: false) { sounds[name] = s }
        }
        if let purr = NSSound(named: "Purr") { sounds["purr"] = purr }
    }

    func play(_ name: String, volume: Float = 0.5) {
        guard on, let base = sounds[name], let s = base.copy() as? NSSound else { return }
        s.volume = volume
        s.play()
    }
}

// MARK: - Things to knock off the ledge

@MainActor
final class Prop {
    let kind: String
    let window = PetWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let layer = CALayer()
    var x: CGFloat, y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0, spin: CGFloat = 0, angle: CGFloat = 0
    var falling = false
    var claimedBy: String?
    let size: CGSize
    let born = ProcessInfo.processInfo.systemUptime

    init(kind: String, image: CGImage, scale: CGFloat, at p: CGPoint) {
        self.kind = kind
        x = p.x
        y = p.y
        size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let side = max(size.width, size.height) * 1.5
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let v = NSView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        v.wantsLayer = true
        layer.contents = image
        layer.magnificationFilter = .nearest
        layer.frame = CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height)
        v.layer?.addSublayer(layer)
        window.contentView = v
        window.setFrame(CGRect(x: 0, y: 0, width: side, height: side), display: false)
        place()
        window.orderFrontRegardless()
    }

    func place() {
        let side = window.frame.width
        window.setFrameOrigin(CGPoint(x: (x - side / 2).rounded(), y: (y - (side - size.height) / 2).rounded()))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(rotationAngle: angle))
        CATransaction.commit()
    }

    func knock(toward dir: CGFloat) {
        falling = true
        vx = dir * .random(in: 90...170)
        vy = .random(in: 120...220)
        spin = dir * -.random(in: 4...9)
    }

    /// Returns false once it has fallen off the bottom of the screen.
    func tick(_ dt: Double) -> Bool {
        guard falling else { return true }
        vy -= 1800 * dt
        x += vx * dt
        y += vy * dt
        angle += spin * dt
        place()
        let bottom = NSScreen.screens.map(\.frame.minY).min() ?? 0
        if y < bottom - 80 { window.orderOut(nil); return false }
        return true
    }
}

// MARK: - Things a pet can stand on

struct Surface: Equatable {
    var id: Int // window number, or a negative number for a screen floor
    var top: CGFloat
    var minX: CGFloat
    var maxX: CGFloat

    func holds(_ x: CGFloat, margin: CGFloat = 0) -> Bool { x >= minX - margin && x <= maxX + margin }
}

@MainActor
final class World {
    private(set) var surfaces: [Surface] = []
    private var last: TimeInterval = 0
    /// Height of a pet in points; the home ledge sits this far below the menu bar.
    var petHeight: CGFloat = 68
    var useWindows = false

    func refresh(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && now - last < 0.25 { return }
        last = now
        var out: [Surface] = []
        // Home: a ledge along the top of each screen, so the pets' ears touch the menu bar.
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.visibleFrame
            out.append(Surface(id: -1 - i, top: f.maxY - petHeight, minX: f.minX + 20, maxX: f.maxX - 20))
        }
        guard useWindows, let primary = NSScreen.screens.first else { surfaces = out; return }
        let mainH = primary.frame.maxY
        let me = getpid()
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let num = w[kCGWindowNumber as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict),
                  b.width > 220, b.height > 120 else { continue }
            let top = mainH - b.minY // CoreGraphics measures from the top; AppKit from the bottom
            // skip window tops that sit under the menu bar or off every screen
            guard NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: 0, dy: -2).contains(CGPoint(x: b.midX, y: top - 4)) }) else { continue }
            out.append(Surface(id: num, top: top, minX: b.minX + 16, maxX: b.maxX - 16))
        }
        surfaces = out
    }

    func surface(id: Int) -> Surface? { surfaces.first { $0.id == id } }

    /// The highest surface at or below `y` that covers `x`.
    func landing(x: CGFloat, below y: CGFloat) -> Surface? {
        surfaces.filter { $0.holds(x) && $0.top <= y + 1 }.max { $0.top < $1.top }
    }

    func floor(near x: CGFloat) -> Surface? {
        surfaces.filter { $0.id < 0 }.min { abs(($0.minX + $0.maxX) / 2 - x) < abs(($1.minX + $1.maxX) / 2 - x) }
    }
}

func userIdleSeconds() -> Double {
    CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
}

// MARK: - The pet's window

final class PetWindow: NSPanel {
    // Let pets sit right up against the menu bar instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    weak var pet: Pet?
    private var downAt: NSPoint = .zero
    private var grabOffset: NSPoint = .zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only the sprite itself is clickable; the space for hearts above it is not.
        guard let pet, pet.spriteRect.contains(convert(point, from: superview)) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        let o = window?.frame.origin ?? .zero
        grabOffset = NSPoint(x: downAt.x - o.x, y: downAt.y - o.y)
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        if !dragging && hypot(p.x - downAt.x, p.y - downAt.y) < 4 { return }
        dragging = true
        pet?.carried(to: NSPoint(x: p.x - grabOffset.x, y: p.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if dragging { pet?.dropped() } else { pet?.clicked() }
        dragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        pet?.app?.showMenu(at: event, in: self)
    }
}

// MARK: - A pet

@MainActor
final class Pet {
    enum State: Equatable {
        case sit, walk(CGFloat), run(CGFloat), sleep, react(String), special(String), act, fall, jump, held
    }

    /// A little routine: each step is a pose, how long it lasts, and frames per second.
    struct Step { var pose: String; var seconds: Double; var fps: Double }
    var steps: [Step] = []
    var purrAt: Double?
    var prop: Prop? // the thing this cat is going to knock off
    var fetching = false // Kai is bringing his rope over

    func perform(_ s: [Step]) {
        steps = s
        go(.act, for: s.reduce(0) { $0 + $1.seconds })
    }

    var hasBap: Bool { book.count(name, "bap") > 0 }

    let name: String
    let kind: Kind
    let book: SpriteBook
    weak var app: AppController?
    let window: PetWindow
    let view: PetView
    let sprite = CALayer()
    let fx = CATextLayer()

    var scale: CGFloat
    var x: CGFloat // centre of the paws, screen coordinates
    var y: CGFloat // bottom of the paws
    var vy: CGFloat = 0
    var surfaceID: Int?
    var state: State = .fall
    var timeLeft: Double = 0
    var clock: Double = 0
    var blinkAt: Double = .random(in: 2...5)
    var jumpFrom = CGPoint.zero, jumpTo = CGPoint.zero, jumpT: Double = 0
    var hasSplat: Bool
    var lastZ: Double = -10

    init(name: String, kind: Kind, book: SpriteBook, scale: CGFloat, at point: CGPoint) {
        self.name = name
        self.kind = kind
        self.book = book
        self.scale = scale
        self.x = point.x
        self.y = point.y
        self.hasSplat = book.count(name, "splat") > 0
        window = PetWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        view = PetView()
        view.wantsLayer = true
        view.pet = self
        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        sprite.magnificationFilter = .nearest
        sprite.contentsGravity = .resize
        view.layer?.addSublayer(sprite)
        fx.alignmentMode = .center
        fx.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        fx.opacity = 0
        view.layer?.addSublayer(fx)
        layout()
        window.orderFrontRegardless()
    }

    var spriteRect: CGRect { CGRect(x: 0, y: 0, width: spriteW * scale, height: spriteH * scale) }

    func layout() {
        let w = spriteW * scale, h = (spriteH + fxRoom) * scale
        window.setFrame(CGRect(x: x - w / 2, y: y - pawGap * scale, width: w, height: h), display: false)
        view.frame = CGRect(x: 0, y: 0, width: w, height: h)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = spriteRect
        fx.frame = CGRect(x: 0, y: spriteH * scale - 6 * scale, width: w, height: 18 * scale)
        fx.fontSize = 9 * scale
        CATransaction.commit()
    }

    func place() {
        let w = spriteW * scale
        window.setFrameOrigin(CGPoint(x: (x - w / 2).rounded(), y: (y - pawGap * scale).rounded()))
    }

    func show(_ frame: String) {
        guard let img = book.image(name, frame) ?? book.image(name, "sit_0") else { return }
        if sprite.contents as! CGImage? !== img {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sprite.contents = img
            CATransaction.commit()
        }
    }

    func float(_ text: String, color: NSColor) {
        fx.string = text
        fx.foregroundColor = color.cgColor
        fx.removeAllAnimations()
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = fx.position.y - 4 * scale
        rise.toValue = fx.position.y + 4 * scale
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let group = CAAnimationGroup()
        group.animations = [rise, fade]
        group.duration = 1.4
        fx.add(group, forKey: "float")
    }

    // MARK: input

    func clicked() {
        guard state != .fall && state != .jump else { return }
        if state == .sleep {
            go(.sit, for: 3)
            float("!", color: .white)
            return
        }
        react()
    }

    /// Each pet's own way of answering a click.
    func react() {
        let pink = NSColor(red: 0.95, green: 0.42, blue: 0.5, alpha: 1)
        switch name {
        case "thea":
            // Thea does not want to be touched.
            perform([Step(pose: "hiss", seconds: 0.7, fps: 4), Step(pose: "swipe", seconds: 1.1, fps: 5), Step(pose: "hiss", seconds: 0.6, fps: 4)])
            app?.sounds.play("hiss", volume: 0.45)
            float("HSSS!", color: NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1))
        case "ivan":
            perform([Step(pose: "meow", seconds: 0.9, fps: 1), Step(pose: "lick", seconds: 2.6, fps: 2.5)])
            app?.sounds.play("mew", volume: 0.55)
            purrAt = 0.9
            float("mew ♪", color: pink)
        default:
            perform([Step(pose: "happy", seconds: 2.6, fps: 9)])
            app?.sounds.play("boof", volume: 0.4)
            float("♥", color: pink)
        }
    }

    func carried(to origin: NSPoint) {
        state = .held
        surfaceID = nil
        let w = spriteW * scale
        x = origin.x + w / 2
        y = origin.y + pawGap * scale
        place()
        show(name == "thea" ? "hiss_0" : kind == .cat ? "meow_0" : "happy_\(Int(ProcessInfo.processInfo.systemUptime * 9) % 3)")
    }

    func dropped() {
        vy = 0
        state = .fall
    }

    // MARK: behaviour

    func go(_ s: State, for seconds: Double) {
        state = s
        timeLeft = seconds
        clock = 0
        lastZ = -10
        blinkAt = .random(in: 2...5)
    }

    var speed: CGFloat { 26 * scale }

    func tick(_ dt: Double, world: World, others: [Pet], quiet: Bool) {
        clock += dt
        timeLeft -= dt
        if state == .held { return }

        if state == .jump {
            jumpT += dt / 0.55
            let t = min(1, jumpT)
            x = jumpFrom.x + (jumpTo.x - jumpFrom.x) * t
            y = jumpFrom.y + (jumpTo.y - jumpFrom.y) * t + CGFloat(sin(.pi * t)) * 26 * scale
            show("walk_1")
            place()
            if t >= 1 { land(on: world.landing(x: x, below: y + 2)); go(.sit, for: .random(in: 2...4)) }
            return
        }

        // Stay on the surface: follow a window that moves, fall if it's gone.
        if state != .fall {
            if let id = surfaceID, let s = world.surface(id: id), s.holds(x, margin: 6) {
                if abs(s.top - y) > 0.5 {
                    if abs(s.top - y) < 60 { y = s.top } else { surfaceID = nil; vy = 0; state = .fall }
                }
            } else {
                surfaceID = nil
                vy = 0
                state = .fall
            }
        }

        if state == .fall {
            vy -= 2400 * dt
            let ny = y + vy * dt
            if let s = world.landing(x: x, below: y), s.top >= ny {
                land(on: s)
                go(.sit, for: .random(in: 1.5...3))
            } else if world.landing(x: x, below: y) == nil, let home = world.surfaces.filter({ $0.holds(x) && $0.id < 0 }).first ?? world.floor(near: x) {
                // dropped below home: hop back up to the ledge
                jumpFrom = CGPoint(x: x, y: y)
                jumpTo = CGPoint(x: min(max(x, home.minX), home.maxX), y: home.top)
                jumpT = 0
                state = .jump
                return
            } else {
                y = ny
                if y < -500, let f = world.floor(near: x) { x = (f.minX + f.maxX) / 2; land(on: f) }
            }
            show(kind == .cat ? "walk_1" : "walk_1")
            place()
            return
        }

        if quiet, state != .sleep, case .react = state {} else if quiet, state != .sleep {
            go(.sleep, for: 30)
        }

        switch state {
        case .sit:
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - x, dy = mouse.y - (y + spriteH * scale / 2)
            var frame = "sit_0"
            if hypot(dx, dy) < 600 {
                frame = dx < -40 ? "sit_0_left" : dx > 40 ? "sit_0_right" : "sit_0"
            } else if kind == .dog {
                frame = "sit_\(Int(clock * 6) % 3)"
            } else {
                frame = Int(clock / 0.9) % 2 == 0 ? "sit_0" : "sit_1"
            }
            if clock > blinkAt {
                frame = "blink_0"
                if clock > blinkAt + 0.15 { blinkAt = clock + .random(in: 2.5...6) }
            }
            show(frame)
        case let .walk(tx), let .run(tx):
            let running: Bool = { if case .run = state { return true }; return false }()
            let v = running ? speed * 3.2 : speed
            let step = CGFloat(dt) * v
            if abs(tx - x) <= step {
                x = tx
                arrived()
            } else {
                x += tx > x ? step : -step
            }
            let fps = running ? 14.0 : 7.0
            if fetching || (kind == .dog && Int(clock) % 7 == 3 && !running) {
                show("carry_\(Int(clock * fps) % 4)")
            } else {
                show("walk_\(Int(clock * fps) % 4)")
            }
            place()
        case .sleep:
            show("sleep_\(Int(clock / 1.1) % 2)")
            if clock - lastZ > 2.6 { lastZ = clock; float("z", color: NSColor(white: 0.95, alpha: 0.9)) }
            if !quiet && userIdleSeconds() < 2 && clock > 3 { go(.sit, for: 3); float("!", color: .white) }
        case let .react(pose):
            let n = max(1, book.count(name, pose.replacingOccurrences(of: "_0", with: "")))
            show(pose.hasSuffix("_0") ? pose : "\(pose)_\(Int(clock * 6) % n)")
        case let .special(pose):
            let n = max(1, book.count(name, pose))
            show("\(pose)_\(Int(clock / 0.8) % n)")
        case .act:
            if let at = purrAt, clock >= at { purrAt = nil; app?.sounds.play("purr", volume: 0.35) }
            if let p = prop, steps.first?.pose == "bap", clock > 0.55, !p.falling {
                p.knock(toward: 1)
                app?.sounds.play("tap", volume: 0.5)
                float(["oops", "bap", "…"].randomElement()!, color: NSColor(white: 0.95, alpha: 1))
                prop = nil
            }
            var t = clock
            for (i, step) in steps.enumerated() {
                if t < step.seconds || i == steps.count - 1 {
                    let n = max(1, book.count(name, step.pose))
                    let f = step.pose == "bap" ? min(i, 1) : Int(min(t, step.seconds - 0.01) * step.fps) % n
                    show("\(step.pose)_\(f)")
                    break
                }
                t -= step.seconds
            }
        default:
            break
        }

        if timeLeft <= 0 && state != .sleep || (state == .sleep && timeLeft <= 0 && userIdleSeconds() < 60) {
            decide(world: world, others: others)
        }
    }

    func arrived() {
        if let p = prop, !p.falling, abs(p.x - x) < 60 * scale {
            // wind up, bap, then sit there looking innocent
            perform([Step(pose: "bap", seconds: 0.55, fps: 0), Step(pose: "bap", seconds: 0.6, fps: 0), Step(pose: "sit", seconds: 1.4, fps: 1)])
            return
        }
        prop?.claimedBy = nil
        prop = nil
        if fetching {
            fetching = false
            perform([Step(pose: "tug", seconds: 3, fps: 6)])
            float("play?", color: NSColor(white: 0.95, alpha: 1))
            app?.sounds.play("boof", volume: 0.3)
            return
        }
        go(.sit, for: .random(in: 2...6))
    }

    func land(on s: Surface?) {
        guard let s else { return }
        y = s.top
        vy = 0
        surfaceID = s.id
        x = min(max(x, s.minX), s.maxX)
        place()
    }

    func decide(world: World, others: [Pet]) {
        guard let id = surfaceID, let here = world.surface(id: id) else { state = .fall; return }
        if name == "thea", let kai = others.first(where: { $0.name == "kai" && $0.surfaceID == id }), abs(kai.x - x) < 70 * scale / 2 {
            perform([Step(pose: "hiss", seconds: 1.2, fps: 4)])
            float("hss", color: NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1))
            return
        }
        if userIdleSeconds() > 90 { go(.sleep, for: 20); return }
        // A cat can't resist something sitting on the ledge.
        if kind == .cat, hasBap, let p = app?.props.first(where: { !$0.falling && $0.claimedBy == nil && abs($0.y - y) < 4 }),
           ProcessInfo.processInfo.systemUptime - p.born > 6, Double.random(in: 0..<1) < 0.6 {
            p.claimedBy = name
            prop = p
            // her bapping paw is on her right, so she always comes at it from the left
            go(.walk(max(p.x - 15 * scale, here.minX)), for: 40)
            return
        }
        // Kai brings his rope to wherever your cursor is.
        if name == "kai", Double.random(in: 0..<1) < 0.12 {
            let mx = min(max(NSEvent.mouseLocation.x, here.minX), here.maxX)
            if abs(mx - x) > 40 {
                fetching = true
                go(.walk(mx), for: 40)
                return
            }
        }
        let roll = Double.random(in: 0..<1)
        let spanX = { CGFloat.random(in: here.minX...max(here.minX + 1, here.maxX)) }
        switch roll {
        case ..<0.34:
            go(.sit, for: .random(in: 3...8))
        case ..<0.66:
            let tx = min(max(x + .random(in: -260...260) * scale / 3, here.minX), here.maxX)
            go(.walk(tx), for: 30)
        case ..<0.72:
            go(.run(spanX()), for: 10)
        case ..<0.80:
            // jump to a nearby window top or back down
            let options = world.surfaces.filter { $0.id != id && abs($0.top - y) < 900 && $0.maxX - $0.minX > 80 }
            if let s = options.randomElement() {
                let tx = min(max(x, s.minX + 10), s.maxX - 10)
                if abs(tx - x) < 400 {
                    jumpFrom = CGPoint(x: x, y: y)
                    jumpTo = CGPoint(x: tx, y: s.top)
                    jumpT = 0
                    surfaceID = nil
                    state = .jump
                    return
                }
            }
            go(.sit, for: 3)
        case ..<0.86:
            go(.sleep, for: .random(in: 15...40))
        case ..<0.93:
            switch name {
            case "kai":
                if Bool.random() { perform([Step(pose: "happy", seconds: 2.4, fps: 9)]) } else { go(.special(Bool.random() ? "pant" : "tug"), for: 4) }
            case "ivan":
                // Ivan grooms a lot, and sometimes flops flat
                if Double.random(in: 0..<1) < 0.65 { perform([Step(pose: "lick", seconds: 4, fps: 2.5)]) } else { go(.special("splat"), for: 6) }
            default:
                // Thea: a quick wash, or a grumpy stare
                if Bool.random() { perform([Step(pose: "lick", seconds: 3, fps: 2.5)]) } else { go(.sit, for: 4); float("hmph", color: NSColor(white: 0.9, alpha: 1)) }
            }
        default:
            // Kai chases a cat on the same surface; cats scatter.
            if kind == .dog, let cat = others.first(where: { $0.kind == .cat && $0.surfaceID == id }) {
                go(.run(cat.x), for: 6)
                cat.go(.run(min(max(cat.x + (cat.x > x ? 1 : -1) * 220, here.minX), here.maxX)), for: 6)
                cat.float("!", color: .white)
            } else {
                go(.walk(spanX()), for: 30)
            }
        }
    }

    func setScale(_ s: CGFloat) {
        scale = s
        layout()
    }

    func close() { window.orderOut(nil) }
}

// MARK: - App

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let names: [(String, Kind)] = [("thea", .cat), ("ivan", .cat), ("kai", .dog)]
    var pets: [String: Pet] = [:]
    var props: [Prop] = []
    var sounds: SoundBank!
    var nextProp: TimeInterval = ProcessInfo.processInfo.systemUptime + (CommandLine.arguments.contains("--demo") ? 3 : .random(in: 40...90))
    let world = World()
    var book: SpriteBook!
    var status: NSStatusItem!
    var timer: Timer?
    let defaults = UserDefaults.standard

    var scale: CGFloat {
        get { CGFloat(defaults.object(forKey: "scale") as? Double ?? 2) }
        set { defaults.set(Double(newValue), forKey: "scale") }
    }

    var quiet: Bool {
        get { defaults.bool(forKey: "quiet") }
        set { defaults.set(newValue, forKey: "quiet") }
    }

    func enabled(_ name: String) -> Bool { defaults.object(forKey: "show.\(name)") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = Bundle.main.resourceURL!.appendingPathComponent("sprites")
        book = SpriteBook(root: root)
        sounds = SoundBank(root: Bundle.main.resourceURL!.appendingPathComponent("sounds"))
        sounds.on = defaults.object(forKey: "sounds") as? Bool ?? true
        world.petHeight = (spriteH - 2) * scale
        world.useWindows = defaults.bool(forKey: "windows")
        world.refresh(force: true)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = book.image("thea", "sit_0") {
            let icon = NSImage(cgImage: img, size: NSSize(width: 20, height: 19))
            status.button?.image = icon
            status.button?.imageScaling = .scaleProportionallyDown
        }
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        for (name, _) in names where enabled(name) { spawn(name) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func spawn(_ name: String) {
        guard pets[name] == nil, let kind = names.first(where: { $0.0 == name })?.1 else { return }
        let floor = world.floor(near: NSEvent.mouseLocation.x)
        let order = CGFloat(names.firstIndex { $0.0 == name } ?? 0)
        let x = (floor.map { $0.minX + ($0.maxX - $0.minX) * (0.3 + 0.2 * order) }) ?? 400
        let p = Pet(name: name, kind: kind, book: book, scale: scale, at: CGPoint(x: x, y: (floor?.top ?? 0)))
        p.app = self
        pets[name] = p
    }

    func tick() {
        world.refresh()
        let all = Array(pets.values)
        for p in all { p.tick(1.0 / 30, world: world, others: all.filter { $0 !== p }, quiet: quiet) }
        props = props.filter { $0.tick(1.0 / 30) }
        let now = ProcessInfo.processInfo.systemUptime
        if now > nextProp {
            nextProp = now + .random(in: 120...300)
            spawnProp()
        }
    }

    /// Leave something on the ledge for the cats to find.
    func spawnProp() {
        guard props.filter({ !$0.falling }).isEmpty, !quiet,
              pets.values.contains(where: { $0.kind == .cat }),
              let cat = pets.values.first(where: { $0.kind == .cat && $0.surfaceID != nil }),
              let ledge = world.surface(id: cat.surfaceID!) else { return }
        let kind = ["pencil", "mug", "yarn"].randomElement()!
        guard let img = book.image("props", kind) else { return }
        let x = CGFloat.random(in: (ledge.minX + 60)...max(ledge.minX + 61, ledge.maxX - 60))
        props.append(Prop(kind: kind, image: img, scale: scale, at: CGPoint(x: x, y: ledge.top)))
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) { build(menu) }

    func build(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Pixel Pets", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        for (name, _) in names {
            let item = NSMenuItem(title: name.capitalized, action: #selector(togglePet(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = pets[name] != nil ? .on : .off
            if let img = book.image(name, "sit_0") { item.image = NSImage(cgImage: img, size: NSSize(width: 18, height: 17)) }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let here = NSMenuItem(title: "Call everyone here", action: #selector(callHere), keyEquivalent: "")
        here.target = self
        menu.addItem(here)
        let snd = NSMenuItem(title: "Sounds", action: #selector(toggleSounds), keyEquivalent: "")
        snd.target = self
        snd.state = sounds.on ? .on : .off
        menu.addItem(snd)
        let drop = NSMenuItem(title: "Leave something for the cats", action: #selector(dropProp), keyEquivalent: "")
        drop.target = self
        menu.addItem(drop)
        let nap = NSMenuItem(title: "Nap time (quiet mode)", action: #selector(toggleQuiet), keyEquivalent: "")
        nap.target = self
        nap.state = quiet ? .on : .off
        menu.addItem(nap)
        let hop = NSMenuItem(title: "Hop onto windows", action: #selector(toggleWindows), keyEquivalent: "")
        hop.target = self
        hop.state = world.useWindows ? .on : .off
        menu.addItem(hop)
        let size = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (label, s) in [("Small", 2.0), ("Medium", 3.0), ("Large", 4.0)] {
            let it = NSMenuItem(title: label, action: #selector(setSize(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = s
            it.state = abs(Double(scale) - s) < 0.01 ? .on : .off
            sub.addItem(it)
        }
        size.submenu = sub
        menu.addItem(size)
        let login = NSMenuItem(title: "Start at login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pixel Pets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func showMenu(at event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        build(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc func togglePet(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        if let p = pets[name] {
            p.close()
            pets[name] = nil
            defaults.set(false, forKey: "show.\(name)")
        } else {
            defaults.set(true, forKey: "show.\(name)")
            spawn(name)
        }
    }

    @objc func callHere() {
        let m = NSEvent.mouseLocation
        for (i, p) in pets.values.enumerated() {
            p.x = m.x + CGFloat(i - 1) * 60 * scale / 3
            p.y = m.y
            p.surfaceID = nil
            p.vy = 0
            p.state = .fall
            p.place()
        }
    }

    @objc func toggleSounds() {
        sounds.on.toggle()
        defaults.set(sounds.on, forKey: "sounds")
    }

    @objc func dropProp() {
        spawnProp()
        if let p = props.last { p.claimedBy = nil }
    }

    @objc func toggleWindows() {
        world.useWindows.toggle()
        defaults.set(world.useWindows, forKey: "windows")
        world.refresh(force: true)
    }

    @objc func toggleQuiet() {
        quiet.toggle()
        if !quiet { for p in pets.values where p.state == .sleep { p.go(.sit, for: 2) } }
    }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Double else { return }
        scale = CGFloat(s)
        world.petHeight = (spriteH - 2) * scale
        world.refresh(force: true)
        for p in pets.values { p.setScale(CGFloat(s)); p.surfaceID = nil; p.state = .fall }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change the login setting"
            a.informativeText = "Move Pixel Pets into your Applications folder and try again.\n\n\(error.localizedDescription)"
            a.runModal()
        }
    }
}

let app = NSApplication.shared
let controller = MainActor.assumeIsolated { AppController() }
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
