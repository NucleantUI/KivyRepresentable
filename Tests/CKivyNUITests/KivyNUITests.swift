import Testing
import CKivyNUI

/// What the host callbacks saw, reached through the table's `context`.
final class HostLog {
    var presents = 0
    var titles: [String] = []
    var closes = 0
}

/// What Kivy's tick saw.
final class KivyLog {
    var ticks: [Double] = []
}

/// The library holds process-wide state, so these run one at a time.
@Suite(.serialized)
struct KivyNUITests {

    private func drain() {
        var event = KivyNUIEvent()
        while kivy_nui_poll_event(&event) {}
    }

    @Test func noHostMeansNoGLAndNoCrash() {
        kivy_nui_set_host(nil)
        #expect(!kivy_nui_is_hosted())
        #expect(kivy_nui_gl() == nil)
        kivy_nui_present()
        kivy_nui_set_title("ignored")
        var metrics = KivyNUIWindowMetrics(width: 9, height: 9, pixel_width: 9, pixel_height: 9, density: 9, dpi: 9)
        kivy_nui_get_window_metrics(&metrics)
        #expect(metrics.width == 0 && metrics.pixel_height == 0)
    }

    @Test func hostCallsAreForwardedWithContext() {
        let log = HostLog()
        let context = Unmanaged.passRetained(log)
        defer { context.release() }

        var gl = KivyNUIGL()
        gl.glClear = { _ in }

        withUnsafePointer(to: &gl) { glPointer in
            var host = KivyNUIHost()
            host.context = context.toOpaque()
            host.gl = glPointer
            host.present = { context in
                Unmanaged<HostLog>.fromOpaque(context!).takeUnretainedValue().presents += 1
            }
            host.set_title = { context, utf8 in
                Unmanaged<HostLog>.fromOpaque(context!).takeUnretainedValue().titles.append(String(cString: utf8!))
            }
            host.request_close = { context in
                Unmanaged<HostLog>.fromOpaque(context!).takeUnretainedValue().closes += 1
            }
            host.get_window_metrics = { _, out in
                out!.pointee = KivyNUIWindowMetrics(width: 800, height: 600, pixel_width: 1600, pixel_height: 1200, density: 2, dpi: 192)
            }
            kivy_nui_set_host(&host)
            defer { kivy_nui_set_host(nil) }

            #expect(kivy_nui_is_hosted())
            #expect(kivy_nui_gl() == glPointer)
            #expect(kivy_nui_gl()!.pointee.glClear != nil)
            #expect(kivy_nui_gl()!.pointee.glDrawArrays == nil)

            kivy_nui_present()
            kivy_nui_present()
            kivy_nui_set_title("Kivy")
            kivy_nui_request_close()
            // Not provided by this host: must be a no-op.
            kivy_nui_show_keyboard()

            var metrics = KivyNUIWindowMetrics()
            kivy_nui_get_window_metrics(&metrics)
            #expect(metrics.width == 800 && metrics.pixel_width == 1600 && metrics.density == 2)
        }
        #expect(log.presents == 2)
        #expect(log.titles == ["Kivy"])
        #expect(log.closes == 1)
    }

    @Test func tickReachesKivyOnlyWhileRegistered() {
        let log = KivyLog()
        let context = Unmanaged.passRetained(log)
        defer { context.release() }

        kivy_nui_tick(1)
        var kivy = KivyNUIKivy()
        kivy.context = context.toOpaque()
        kivy.tick = { context, dt in
            Unmanaged<KivyLog>.fromOpaque(context!).takeUnretainedValue().ticks.append(dt)
        }
        kivy_nui_set_kivy(&kivy)
        kivy_nui_tick(0.016)
        kivy_nui_tick(0.017)
        kivy_nui_set_kivy(nil)
        kivy_nui_tick(2)
        #expect(log.ticks == [0.016, 0.017])
    }

    @Test func eventsComeOutInOrderPastTheInitialCapacity() {
        drain()
        for i in 0..<200 {
            var event = KivyNUIEvent()
            event.type = KIVY_NUI_EVENT_MOUSE_MOTION
            event.mouse = KivyNUIMouseEvent(x: Int32(i), y: Int32(-i), button: 0)
            kivy_nui_push_event(&event)
        }
        var event = KivyNUIEvent()
        for i in 0..<200 {
            #expect(kivy_nui_poll_event(&event))
            #expect(event.type == KIVY_NUI_EVENT_MOUSE_MOTION)
            #expect(event.mouse.x == Int32(i) && event.mouse.y == Int32(-i))
        }
        #expect(!kivy_nui_poll_event(&event))
    }

    @Test func noneEventsAreDropped() {
        drain()
        var event = KivyNUIEvent()
        kivy_nui_push_event(&event)
        #expect(!kivy_nui_poll_event(&event))
    }

    @Test func dropTextIsCopiedAndLivesUntilTheNextPoll() {
        drain()
        var path = Array("/tmp/a.png".utf8CString)
        path.withUnsafeMutableBufferPointer { buffer in
            var event = KivyNUIEvent()
            event.type = KIVY_NUI_EVENT_DROP_FILE
            event.drop = KivyNUIDropEvent(utf8: buffer.baseAddress, x: 0, y: 0)
            kivy_nui_push_event(&event)
            // The caller's buffer can change right after the push.
            buffer[1] = CChar(UInt8(ascii: "X"))
        }
        var event = KivyNUIEvent()
        #expect(kivy_nui_poll_event(&event))
        #expect(event.type == KIVY_NUI_EVENT_DROP_FILE)
        #expect(String(cString: event.drop.utf8) == "/tmp/a.png")
        #expect(!kivy_nui_poll_event(&event))
    }

    @Test func textIsAlwaysTerminated() {
        drain()
        var event = KivyNUIEvent()
        event.type = KIVY_NUI_EVENT_TEXT_INPUT
        withUnsafeMutableBytes(of: &event.text.utf8) { bytes in
            for i in bytes.indices { bytes[i] = UInt8(ascii: "a") }
        }
        kivy_nui_push_event(&event)
        var out = KivyNUIEvent()
        #expect(kivy_nui_poll_event(&out))
        let text = withUnsafeBytes(of: out.text.utf8) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        #expect(text == String(repeating: "a", count: Int(KIVY_NUI_TEXT_SIZE) - 1))
    }
}
