//
//  KivyNUILibrary+Wasm.swift
//  KivyRepresentable
//
//  The browser: one module, no shared libraries. The C api is compiled into
//  the app and exported (KivyRepresentable's linker settings); Kivy's
//  modules, which Python loads next to the app, call that copy.
//

#if os(WASI)
import CKivyNUI

extension KivyNUILibrary {
    /// The C api compiled into the app.
    static func linkedIntoTheApp() -> KivyNUILibrary? {
        KivyNUILibrary(
            setHost: kivy_nui_set_host,
            pushEvent: kivy_nui_push_event,
            tick: kivy_nui_tick,
            isHosted: kivy_nui_is_hosted
        )
    }

    /// There is no library to open in the browser.
    static func open(_ name: String) throws -> KivyNUILibrary {
        throw LoadError.open("no shared libraries in the browser; the C api is the app's own")
    }
}
#endif
