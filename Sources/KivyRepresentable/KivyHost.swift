//
//  KivyHost.swift
//  KivyRepresentable
//
//  The host end of the shared C api: what Kivy's `nui` window talks to. It
//  registers before Python starts, makes Kivy's GL context when Kivy's
//  window asks (ngl_nui.pyx), answers Kivy's window calls, and forwards
//  input and display-sync ticks to Kivy.
//
//  Kivy is a singleton, so one host is registered at a time.
//

import CKivyNUI

public final class KivyHost: @unchecked Sendable {

    public let library: KivyNUILibrary
    public let device: KivyGLDevice

    /// The window as Kivy sees it; `resize` changes it.
    public private(set) var metrics: KivyNUIWindowMetrics

    /// Kivy's GL context, while its window has one.
    public private(set) var gl: KivyGL?

    /// Text and images for Kivy's `nui` providers, drawn into its textures.
    public let providers = KivyProviders()

    /// Called with the new context, before Kivy draws into it — where a
    /// window points `presentTarget` at its node's image.
    public var onContextCreated: ((KivyGL) -> Void)?
    /// After each of Kivy's frames has been submitted.
    public var onPresent: (() -> Void)?
    public var onTitle: ((String) -> Void)?
    public var onCursor: ((KivyNUICursor) -> Void)?
    public var onCursorVisible: ((Bool) -> Void)?
    public var onShowKeyboard: (() -> Void)?
    public var onHideKeyboard: (() -> Void)?
    /// Kivy stopped (App.stop / Window.close).
    public var onRequestClose: (() -> Void)?

    /// The registered host, kept alive while registered: the C side holds
    /// it unretained.
    nonisolated(unsafe) private static var registered: KivyHost?

    public init(library: KivyNUILibrary, device: KivyGLDevice, metrics: KivyNUIWindowMetrics) {
        self.library = library
        self.device = device
        self.metrics = metrics
    }

    /// Registers with the shared C api. Call before Python starts.
    public func register() {
        Self.registered?.unregister()
        Self.registered = self
        var host = KivyNUIHost()
        host.context = Unmanaged.passUnretained(self).toOpaque()
        host.gl = UnsafePointer(KivyGL.table)
        host.create_gl_context = { context in
            KivyHost.from(context).createContext()
        }
        host.destroy_gl_context = { context in
            KivyHost.from(context).destroyContext()
        }
        host.present = { context in
            KivyHost.from(context).present()
        }
        host.get_window_metrics = { context, out in
            out?.pointee = KivyHost.from(context).metrics
        }
        host.set_title = { context, utf8 in
            KivyHost.from(context).onTitle?(utf8.map { String(cString: $0) } ?? "")
        }
        host.set_system_cursor = { context, cursor in
            KivyHost.from(context).onCursor?(cursor)
        }
        host.set_cursor_visible = { context, visible in
            KivyHost.from(context).onCursorVisible?(visible)
        }
        host.show_keyboard = { context in
            KivyHost.from(context).onShowKeyboard?()
        }
        host.hide_keyboard = { context in
            KivyHost.from(context).onHideKeyboard?()
        }
        host.request_close = { context in
            KivyHost.from(context).onRequestClose?()
        }
        host.text_extents = { context, font, utf8, width, height in
            guard let font, let utf8,
                  let size = KivyHost.from(context).providers.extents(font.pointee, String(cString: utf8))
            else { return false }
            width?.pointee = size.width
            height?.pointee = size.height
            return true
        }
        host.font_metrics = { context, font, ascent, descent in
            guard let font, let metrics = KivyHost.from(context).providers.metrics(font.pointee) else { return false }
            ascent?.pointee = metrics.ascent
            descent?.pointee = metrics.descent
            return true
        }
        host.draw_text = { context, texture, width, height, runs, count in
            let host = KivyHost.from(context)
            guard let gl = host.gl else { return false }
            do {
                try host.providers.drawText(
                    UnsafeBufferPointer(start: runs, count: runs == nil ? 0 : Int(max(0, count))),
                    texture: texture, width: Int(width), height: Int(height), gl: gl
                )
                return true
            } catch {
                return false
            }
        }
        host.image_size = { context, data, size, width, height in
            guard let data,
                  let image = KivyHost.from(context).providers.imageSize(UnsafeRawBufferPointer(start: data, count: size))
            else { return false }
            width?.pointee = image.width
            height?.pointee = image.height
            return true
        }
        host.draw_image = { context, texture, width, height, data, size in
            let host = KivyHost.from(context)
            guard let gl = host.gl, let data else { return false }
            return (try? host.providers.drawImage(
                UnsafeRawBufferPointer(start: data, count: size),
                texture: texture, width: Int(width), height: Int(height), gl: gl
            )) ?? false
        }
        host.image_pixels = { context, data, size, out, outSize in
            guard let data, let out else { return false }
            return KivyHost.from(context).providers.imagePixels(
                UnsafeRawBufferPointer(start: data, count: size),
                into: UnsafeMutableRawBufferPointer(start: out, count: outSize)
            )
        }
        library.setHost(&host)
    }

    public func unregister() {
        guard Self.registered === self else { return }
        library.setHost(nil)
        destroyContext()
        Self.registered = nil
    }

    private static func from(_ context: UnsafeMutableRawPointer?) -> KivyHost {
        Unmanaged<KivyHost>.fromOpaque(context!).takeUnretainedValue()
    }

    // MARK: - Kivy's calls

    private func createContext() -> Bool {
        destroyContext()
        do {
            let gl = try KivyGL(device: device, width: Int(metrics.pixel_width), height: Int(metrics.pixel_height))
            self.gl = gl
            KivyGL.current = gl
            onContextCreated?(gl)
            return true
        } catch {
            return false
        }
    }

    private func destroyContext() {
        guard let gl else { return }
        if KivyGL.current === gl { KivyGL.current = nil }
        self.gl = nil
    }

    private func present() {
        gl?.present()
        onPresent?()
    }

    // MARK: - The host's calls

    /// One display-sync frame: Kivy polls its events, runs its clock, draws
    /// and presents.
    public func tick(_ dt: Double) {
        library.tick(dt)
    }

    public func push(_ event: KivyNUIEvent) {
        var event = event
        library.pushEvent(&event)
    }

    /// The window changed size: framebuffer 0 follows, and Kivy hears it
    /// the way SDL told it.
    public func resize(_ metrics: KivyNUIWindowMetrics) {
        self.metrics = metrics
        try? gl?.resizeDefaultFramebuffer(width: Int(metrics.pixel_width), height: Int(metrics.pixel_height))
        var event = KivyNUIEvent()
        event.type = KIVY_NUI_EVENT_WINDOW_RESIZED
        event.window = KivyNUIWindowEvent(data1: metrics.width, data2: metrics.height)
        push(event)
    }

    /// Framebuffer 0 as RGBA rows, bottom row first — Kivy's last frame, as
    /// glReadPixels gives it.
    public func readFramebuffer() -> [UInt8]? {
        guard let gl else { return nil }
        let width = Int(metrics.pixel_width), height = Int(metrics.pixel_height)
        let previous = gl.boundFramebuffer
        gl.boundFramebuffer = 0
        defer { gl.boundFramebuffer = previous }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        gl.readPixels(0, 0, GLsizei(width), GLsizei(height), GL.rgba, GL.unsignedByte, &pixels)
        return pixels
    }
}
