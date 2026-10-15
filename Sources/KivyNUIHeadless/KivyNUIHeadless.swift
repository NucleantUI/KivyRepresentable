//
//  KivyNUIHeadless.swift
//  KivyNUIHeadless
//
//  A `KivyHost` on a device of its own, with no window, for a process
//  where Python is already running (tests): load this library, start the
//  host, then import Kivy. Frames are read back instead of shown.
//

import CKivyNUI
import KivyRepresentable

nonisolated(unsafe) private var host: KivyHost?

/// Registers a headless host with the shared library at `library_path`
/// (the libCKivyNUI Kivy's extensions link). The window is `width` x
/// `height` points at `density` pixels per point.
@_cdecl("kivy_nui_headless_start")
public func kivy_nui_headless_start(_ libraryPath: UnsafePointer<CChar>?, _ width: Int32, _ height: Int32, _ density: Float) -> Bool {
    do {
        let library = try KivyNUILibrary.load(path: libraryPath.map { String(cString: $0) })
        let metrics = KivyNUIWindowMetrics(
            width: width, height: height,
            pixel_width: Int32((Float(width) * density).rounded()),
            pixel_height: Int32((Float(height) * density).rounded()),
            density: density, dpi: 96 * density
        )
        let started = KivyHost(library: library, device: try KivyGLDevice.headless(), metrics: metrics)
        started.register()
        host = started
        return true
    } catch {
        print("kivy_nui_headless_start: \(error)")
        return false
    }
}

/// Framebuffer 0 into `out` (pixel_width * pixel_height * 4 bytes, RGBA,
/// bottom row first). False before Kivy has a GL context.
@_cdecl("kivy_nui_headless_read")
public func kivy_nui_headless_read(_ out: UnsafeMutablePointer<UInt8>?) -> Bool {
    guard let out, let pixels = host?.readFramebuffer() else { return false }
    out.update(from: pixels, count: pixels.count)
    return true
}

@_cdecl("kivy_nui_headless_stop")
public func kivy_nui_headless_stop() {
    host?.unregister()
    host = nil
}
