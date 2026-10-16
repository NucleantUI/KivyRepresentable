//
//  KivyWindowGroup.swift
//  KivyRepresentable
//
//  A window whose content is a Kivy app. The window is an ordinary
//  NucleantUI one; Kivy's frames reach it through a `.kivy` slot added to its
//  engine, on top of the (empty) view tree's canvas:
//
//    - when the window's content first appears, the session adds the slot,
//      registers the host with the libCKivyNUI Kivy loaded, and runs the
//      window's module as `__main__` in the app's Python
//      (`@Environment(\.kivyLauncher)`, started by `KivyApp` at launch) —
//      `App.run()` returns, since the host ticks Kivy from here on;
//    - every engine frame (`onUpdate`) ticks Kivy, which draws and presents
//      into the slot's image before the frame composites it;
//    - presses and drags on the window go to Kivy as SDL's mouse events.
//
//  Only a `KivyApp` can show one: its windows render with `KivyRenderNode`.
//

import CKivyNUI
@preconcurrency import CVulkan
import NucleantVulkan
import NucleantUI
import NucleantWindow

public struct KivyWindowGroup: Scene {
    let title: String
    let session: KivySession

    /// A window running the Python module `module` as `__main__`.
    public init(_ title: String = "Kivy", module: String) {
        self.title = title
        self.session = KivySession(module: module)
    }

    public var body: Never { fatalError("KivyWindowGroup is a primitive scene") }

    public func _makeWindows<Node: NucleantContainerNode>() -> [HostingWindow<Node>] {
        let window = HostingWindow<Node>(title: title, root: KivyView(session: session))
        session.window = window as? HostingWindow<KivyRenderNode>
        if session.window == nil {
            print("KivyWindowGroup: the app renders with \(Node.self); Kivy needs a KivyApp (KivyRenderNode)")
        }
        return [window]
    }

    public func _lowerCommands(into menuBar: MenuBar) {}
}

/// Fills the window and passes the pointer on to Kivy. Draws nothing:
/// Kivy's slot covers it.
@View
struct KivyView {
    let session: KivySession
    @Environment(\.displayScale) var displayScale
    @Environment(\.kivyLauncher) var launcher

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { session.drag(to: $0.location) }
                    .onEnded { session.release(at: $0.location) }
            )
            .onAppear { session.start(launcher: launcher, displayScale: displayScale) }
            .onChange(of: displayScale) { _, scale in session.displayScale = scale }
    }
}

@MainActor
final class KivySession {
    let module: String
    weak var window: HostingWindow<KivyRenderNode>?
    var displayScale: Double = 1

    private var host: KivyHost?
    private var node: KivyShaderNode<KivyRenderNode>?
    private var container: KivyRenderNode?
    private var device: KivyGLDevice?
    private var pixelSize = (width: 0, height: 0)
    private var pressed = false

    init(module: String) {
        self.module = module
    }

    func start(launcher: KivyLauncher, displayScale: Double) {
        guard host == nil, let window, let engine = window.renderEngine else { return }
        guard launcher.isLaunched else {
            print("KivyWindowGroup: no Python; a KivyApp starts it at launch")
            return
        }
        self.displayScale = displayScale > 0 ? displayScale : 1
        pixelSize = (max(1, window.win_rect.z), max(1, window.win_rect.w))
        do {
            let device = try KivyGLDevice(engine: engine)
            let node = try KivyShaderNode<KivyRenderNode>.make(device: device, width: pixelSize.width, height: pixelSize.height)
            let container = KivyRenderNode(id: Int.random(in: 1...Int.max), context: .kivy(node))
            container.observeContext()
            engine.append(container)

            // The host registers with the C api Kivy's nui modules use. Where
            // the app has it compiled in (the browser), before Kivy is
            // imported at all — so Kivy's text and image providers, picked at
            // its first import, see a host. Where it is libCKivyNUI, Kivy's
            // modules load it, so they come first.
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

            self.device = device
            self.node = node
            self.container = container
            self.host = host
            engine.onUpdate = { [weak self] dt in
                MainActor.assumeIsolated { self?.frame(dt) }
            }
            try launcher.runModule(module)
        } catch {
            print("KivyWindowGroup: \(error)")
        }
    }

    /// The window as Kivy sees it, in points, from the window's pixels.
    private func metrics() -> KivyNUIWindowMetrics {
        let scale = displayScale > 0 ? displayScale : 1
        return KivyNUIWindowMetrics(
            width: Int32((Double(pixelSize.width) / scale).rounded()),
            height: Int32((Double(pixelSize.height) / scale).rounded()),
            pixel_width: Int32(pixelSize.width), pixel_height: Int32(pixelSize.height),
            density: Float(scale), dpi: Float(96 * scale)
        )
    }

    /// One engine frame: follow the window's size, then let Kivy run a pass
    /// of its loop, which presents into the slot this frame composites.
    private func frame(_ dt: Double) {
        guard let host, let window else { return }
        let size = (max(1, window.win_rect.z), max(1, window.win_rect.w))
        if size != pixelSize {
            pixelSize = size
            resizeSlot()
            host.resize(metrics())
        }
        host.tick(dt)
    }

    private func resizeSlot() {
        guard let node, let container, let device, let engine = window?.renderEngine else { return }
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
            print("KivyWindowGroup: resizing Kivy's image failed: \(error)")
        }
    }

    // MARK: - Pointer, as SDL reported it: window points, top-left

    func drag(to location: Point) {
        if !pressed {
            pressed = true
            push(KIVY_NUI_EVENT_MOUSE_MOTION, location)
            push(KIVY_NUI_EVENT_MOUSE_BUTTON_DOWN, location)
        } else {
            push(KIVY_NUI_EVENT_MOUSE_MOTION, location)
        }
    }

    func release(at location: Point) {
        pressed = false
        push(KIVY_NUI_EVENT_MOUSE_BUTTON_UP, location)
    }

    private func push(_ type: KivyNUIEventType, _ location: Point) {
        var event = KivyNUIEvent()
        event.type = type
        event.mouse = KivyNUIMouseEvent(x: Int32(location.x.rounded()), y: Int32(location.y.rounded()), button: 1)
        host?.push(event)
    }
}
