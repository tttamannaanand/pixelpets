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

    func refresh(force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !force && now - last < 0.25 { return }
        last = now
        var out: [Surface] = []
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.visibleFrame
            out.append(Surface(id: -1 - i, top: f.minY, minX: f.minX + 20, maxX: f.maxX - 20))
        }
        guard let primary = NSScreen.screens.first else { surfaces = out; return }
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
        case sit, walk(CGFloat), run(CGFloat), sleep, react(String), special(String), fall, jump, held
    }

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
        switch kind {
        case .cat: go(.react("meow_0"), for: 1.3)
        case .dog: go(.react(Bool.random() ? "tug" : "pant"), for: 2.2)
        }
        float("♥", color: NSColor(red: 0.95, green: 0.42, blue: 0.5, alpha: 1))
    }

    func carried(to origin: NSPoint) {
        state = .held
        surfaceID = nil
        let w = spriteW * scale
        x = origin.x + w / 2
        y = origin.y + pawGap * scale
        place()
        show(kind == .cat ? "meow_0" : "pant_1")
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
            if abs(tx - x) <= step { x = tx; go(.sit, for: .random(in: 2...6)) } else { x += tx > x ? step : -step }
            let fps = running ? 14.0 : 7.0
            show("walk_\(Int(clock * fps) % 4)")
            if kind == .dog, Int(clock) % 7 == 3, !running { show("carry_\(Int(clock * fps) % 4)") }
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
        default:
            break
        }

        if timeLeft <= 0 && state != .sleep || (state == .sleep && timeLeft <= 0 && userIdleSeconds() < 60) {
            decide(world: world, others: others)
        }
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
        if userIdleSeconds() > 90 { go(.sleep, for: 20); return }
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
            let options = world.surfaces.filter { $0.id != id && abs($0.top - y) < 420 * scale / 3 && $0.maxX - $0.minX > 80 }
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
            if kind == .dog {
                go(.special(Bool.random() ? "pant" : "tug"), for: 4)
            } else if hasSplat {
                go(.special("splat"), for: 6)
            } else {
                go(.react("meow_0"), for: 1.2)
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
    let world = World()
    var book: SpriteBook!
    var status: NSStatusItem!
    var timer: Timer?
    let defaults = UserDefaults.standard

    var scale: CGFloat {
        get { CGFloat(defaults.object(forKey: "scale") as? Double ?? 3) }
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
        let p = Pet(name: name, kind: kind, book: book, scale: scale, at: CGPoint(x: x, y: (floor?.top ?? 0) + 300))
        p.app = self
        pets[name] = p
    }

    func tick() {
        world.refresh()
        let all = Array(pets.values)
        for p in all { p.tick(1.0 / 30, world: world, others: all.filter { $0 !== p }, quiet: quiet) }
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
        let nap = NSMenuItem(title: "Nap time (quiet mode)", action: #selector(toggleQuiet), keyEquivalent: "")
        nap.target = self
        nap.state = quiet ? .on : .off
        menu.addItem(nap)
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
            p.y = m.y + 40
            p.surfaceID = nil
            p.vy = 0
            p.state = .fall
            p.place()
        }
    }

    @objc func toggleQuiet() {
        quiet.toggle()
        if !quiet { for p in pets.values where p.state == .sleep { p.go(.sit, for: 2) } }
    }

    @objc func setSize(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Double else { return }
        scale = CGFloat(s)
        for p in pets.values { p.setScale(CGFloat(s)) }
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
