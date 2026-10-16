//
//  KivyAppView.swift
//  KivyRepresentable
//
//  A Kivy app as a view, in any window of a `KivyApp` — what
//  `KivyWindowGroup` is for a whole window. Kivy's frames reach the view
//  through a `.kivy` slot composited at the view's frame:
//
//    - the view is laid out by `KivyAppFrame`, a `Layout` that fills what it
//      is offered and tells the session where that is in the window, every
//      pass;
//    - the window's engine reaches the session through the window's own
//      nodes, which are `KivyRenderNode`s: the first one its draw updates
//      after the pass hands the engine over (`KivyAppSession.handOver`);
//    - from then on every engine frame (`onUpdate`) starts Kivy once — the
//      slot, the host, the view's module run as `__main__`, as
//      KivyWindowGroup does — then keeps the slot on the view's frame and
//      ticks Kivy;
//    - the window's input over the view goes to Kivy as SDL's events, in
//      the view's own points, before the views see it (KivyInput, the
//      window's input delegate while the view is in the tree).
//
//  Kivy runs once per process — one window, one app — so there is one
//  session, started by the first KivyAppView to appear, and every
//  KivyAppView shows it. A view that leaves the tree hides the slot and
//  stops ticking Kivy; back in the tree (a new view, as far as its state
//  goes), it finds the same session and shows and ticks it again.
//

import CKivyNUI
@preconcurrency import CVulkan
import NucleantVulkan
import NucleantUI

/// A view running the Python module `module` as `__main__`: a Kivy app,
/// shown in the view's frame.
///
/// ```swift
/// WindowGroup("Editor") {
///     HStack {
///         Sidebar()
///         KivyAppView(module: "playground")
///     }
/// }
/// ```
///
/// It takes whatever space it is offered, so give it a `.frame` where it
/// has nothing to fill. Only a `KivyApp` can show one: its windows render
/// with `KivyRenderNode`.
@View
public struct KivyAppView {
    let module: String
    @Environment(\.displayScale) var displayScale
    @Environment(\.kivyLauncher) var launcher
    @Environment(\.windowInput) var windowInput

    public init(module: String, _viewID: ViewID = #viewID) {
        self.module = module
        self._viewID = _viewID
    }

    public var body: some View {
        let session = KivyAppSession.running(module: module)
        KivyAppFrame(session: session) {
            Color.clear
        }
        .onAppear { session.appear(launcher: launcher, displayScale: displayScale, windowInput: windowInput) }
        .onDisappear { session.disappear() }
        .onChange(of: displayScale) { _, scale in session.displayScale = scale }
    }
}

/// Fills what it is offered, and tells the session where that is in the
/// window — the frame Kivy's slot is composited at.
struct KivyAppFrame: Layout {
    let session: KivyAppSession

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> Size {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: Rect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
        session.placed(in: bounds)
    }
}

@MainActor
final class KivyAppSession {

    /// The process's Kivy, once a KivyAppView has asked for it.
    static var current: KivyAppSession?

    /// The session every KivyAppView shows: the one running, or a new one
    /// for `module`. Kivy runs one app per process, so a view asking for
    /// another module while one runs shows the one running.
    static func running(module: String) -> KivyAppSession {
        if let current {
            if current.module != module {
                print("KivyAppView: Kivy already runs \(current.module); one Kivy app per process, so not \(module)")
            }
            return current
        }
        let session = KivyAppSession(module: module)
        current = session
        return session
    }

    /// Laid out in a pass whose window hasn't drawn since: the window's next
    /// draw — right after its pass — hands them its engine.
    static var awaitingEngine: [KivyAppSession] = []

    /// Gives `engine` to the sessions waiting for one; whether there were
    /// any. Called by every `KivyRenderNode` the engine updates, so by the
    /// first one updated in the draw that follows the pass that placed them.
    static func handOver(_ engine: VulkanRenderEngine<KivyRenderNode>) -> Bool {
        guard !awaitingEngine.isEmpty else { return false }
        let sessions = awaitingEngine
        awaitingEngine.removeAll()
        for session in sessions { session.attach(engine) }
        return true
    }

    let module: String
    var displayScale: Double = 1 {
        didSet {
            guard displayScale != oldValue, host != nil else { return }
            try? launcher?.setDensity(displayScale)
        }
    }

    /// The view's frame in its window, in points, as last laid out.
    private(set) var bounds: Rect = .zero
    private(set) weak var engine: VulkanRenderEngine<KivyRenderNode>?
    /// In the tree: shown and ticked.
    private(set) var isShown = false

    private var launcher: KivyLauncher?
    private var host: KivyHost?
    /// The window's input over the view, for Kivy.
    private(set) lazy var input = KivyInput { [weak self] event in self?.host?.push(event) }
    private weak var windowInput: WindowInput?
    private var node: KivyShaderNode<KivyRenderNode>?
    private var container: KivyRenderNode?
    private var device: KivyGLDevice?
    private var pixelSize = (width: 0, height: 0)

    init(module: String) {
        self.module = module
    }

    /// The view's frame in pixels: where the slot is composited, and the
    /// size Kivy draws at.
    var pixelFrame: (x: Int, y: Int, width: Int, height: Int) {
        let scale = displayScale > 0 ? displayScale : 1
        return (
            Int((bounds.minX * scale).rounded(.down)),
            Int((bounds.minY * scale).rounded(.down)),
            max(1, Int((bounds.width * scale).rounded(.up))),
            max(1, Int((bounds.height * scale).rounded(.up)))
        )
    }

    // MARK: - From the view

    func placed(in rect: Rect) {
        bounds = rect
        input.frame = rect
        if engine == nil, !Self.awaitingEngine.contains(where: { $0 === self }) {
            Self.awaitingEngine.append(self)
        }
    }

    func appear(launcher: KivyLauncher, displayScale: Double, windowInput: WindowInput?) {
        self.launcher = launcher
        self.displayScale = displayScale > 0 ? displayScale : 1
        self.windowInput = windowInput
        windowInput?.delegate = input
        isShown = true
        container?.compositesToWindow = true
    }

    func disappear() {
        isShown = false
        if windowInput?.delegate === input { windowInput?.delegate = nil }
        container?.compositesToWindow = false
        Self.awaitingEngine.removeAll { $0 === self }
    }

    // MARK: - From the engine

    private func attach(_ engine: VulkanRenderEngine<KivyRenderNode>) {
        self.engine = engine
        let previous = engine.onUpdate
        engine.onUpdate = { [weak self] dt in
            previous?(dt)
            MainActor.assumeIsolated { self?.step(dt) }
        }
    }

    /// One engine frame: start Kivy the first time, then follow the view's
    /// frame and let Kivy run a pass of its loop, which presents into the
    /// slot this frame composites.
    private func step(_ dt: Double) {
        guard isShown, let engine else { return }
        guard let host, let container else {
            start(engine)
            return
        }
        let frame = pixelFrame
        if (frame.width, frame.height) != pixelSize {
            pixelSize = (frame.width, frame.height)
            resizeSlot()
            host.resize(metrics())
        }
        if let node {
            container.compositeRect = SIMD4(Double(frame.x), Double(frame.y), Double(node.width), Double(node.height))
        }
        input.keyboard.readSystemKeyboard()
        host.tick(dt)
    }

    private func start(_ engine: VulkanRenderEngine<KivyRenderNode>) {
        guard host == nil, let launcher else { return }
        guard launcher.isLaunched else {
            print("KivyAppView: no Python; a KivyApp starts it at launch")
            isShown = false
            return
        }
        let frame = pixelFrame
        pixelSize = (frame.width, frame.height)
        do {
            let device = try KivyGLDevice(engine: engine)
            let node = try KivyShaderNode<KivyRenderNode>.make(device: device, width: pixelSize.width, height: pixelSize.height)
            let container = KivyRenderNode(id: Int.random(in: 1...Int.max), context: .kivy(node))
            container.compositeRect = SIMD4(Double(frame.x), Double(frame.y), Double(node.width), Double(node.height))
            container.observeContext()
            engine.append(container)

            // As in KivyWindowGroup: where the app has the C api compiled in
            // (the browser), the host registers before Kivy is imported;
            // where it is libCKivyNUI, Kivy's modules load it first.
            let library: KivyNUILibrary
            if let linked = KivyNUILibrary.linkedIntoTheApp() {
                library = linked
            } else {
                try launcher.importModule("kivy.graphics.ngl_backend.ngl_nui")
                library = try KivyNUILibrary.loadedByKivy()
            }
            let host = KivyHost(library: library, device: device, metrics: metrics())
            host.onContextCreated = { [weak node] gl in
                guard let node else { return }
                gl.presentTarget = (node.image, Int(node.width), Int(node.height), VK_IMAGE_LAYOUT_UNDEFINED)
            }
            host.onPresent = { [weak node] in
                node?.hasContent = true
                node?.dirty.toggle()
            }
            host.register()
            input.keyboard.connectSystemKeyboard(host)

            self.device = device
            self.node = node
            self.container = container
            self.host = host
            try launcher.setDensity(displayScale)
            try launcher.runModule(module)
        } catch {
            print("KivyAppView: \(error)")
        }
    }

    /// The view as Kivy sees its window, in points, from its pixels.
    private func metrics() -> KivyNUIWindowMetrics {
        let scale = displayScale > 0 ? displayScale : 1
        return KivyNUIWindowMetrics(
            width: Int32((Double(pixelSize.width) / scale).rounded()),
            height: Int32((Double(pixelSize.height) / scale).rounded()),
            pixel_width: Int32(pixelSize.width), pixel_height: Int32(pixelSize.height),
            density: Float(scale), dpi: Float(96 * scale)
        )
    }

    private func resizeSlot() {
        guard let node, let container, let device, let engine else { return }
        do {
            let old = try node.resize(device: device, width: pixelSize.width, height: pixelSize.height)
            engine.invalidateComposite(id: container.id)
            let vkDevice = device.device
            engine.releaseAfterInFlightFrames {
                vkDestroyImageView(vkDevice, old.view, nil)
                vkDestroyImage(vkDevice, old.image, nil)
                if let memory = old.memory { vkFreeMemory(vkDevice, memory, nil) }
            }
            host?.gl?.presentTarget = (node.image, Int(node.width), Int(node.height), VK_IMAGE_LAYOUT_UNDEFINED)
        } catch {
            print("KivyAppView: resizing Kivy's image failed: \(error)")
        }
    }
}
