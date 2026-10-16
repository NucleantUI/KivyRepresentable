//
//  KivyNUILibrary+Native.swift
//  KivyRepresentable
//
//  macOS, iOS, Linux, Android: Kivy's modules link libCKivyNUI, a shared
//  library the host opens too.
//

#if !os(WASI)
import Foundation
import CKivyNUI

extension KivyNUILibrary {
    /// None compiled into the app for Kivy: it uses libCKivyNUI.
    static func linkedIntoTheApp() -> KivyNUILibrary? { nil }

    /// The library `name` names, opened with the loader.
    static func open(_ name: String) throws -> KivyNUILibrary {
        guard let handle = dlopen(name, RTLD_NOW | RTLD_GLOBAL) else {
            throw LoadError.open(String(cString: dlerror()))
        }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let pointer = dlsym(handle, name) else { throw LoadError.missing(name) }
            return unsafeBitCast(pointer, to: type)
        }
        return KivyNUILibrary(
            setHost: try symbol("kivy_nui_set_host", as: (@convention(c) (UnsafePointer<KivyNUIHost>?) -> Void).self),
            pushEvent: try symbol("kivy_nui_push_event", as: (@convention(c) (UnsafePointer<KivyNUIEvent>?) -> Void).self),
            tick: try symbol("kivy_nui_tick", as: (@convention(c) (Double) -> Void).self),
            isHosted: try symbol("kivy_nui_is_hosted", as: (@convention(c) () -> Bool).self)
        )
    }
}
#endif
