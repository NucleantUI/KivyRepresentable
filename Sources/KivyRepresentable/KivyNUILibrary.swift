//
//  KivyNUILibrary.swift
//  KivyRepresentable
//
//  The shared C api, reached through the one `libCKivyNUI` in the process —
//  the library Kivy's Cython extensions link. This module compiles the same
//  C in for its types, but a host registered with that copy would be one
//  Kivy never sees: each copy has its own state. So the host's calls go
//  through the shared library, opened by path.
//

import Foundation
import CKivyNUI

public struct KivyNUILibrary: @unchecked Sendable {
    public let setHost: @convention(c) (UnsafePointer<KivyNUIHost>?) -> Void
    public let pushEvent: @convention(c) (UnsafePointer<KivyNUIEvent>?) -> Void
    public let tick: @convention(c) (Double) -> Void
    public let isHosted: @convention(c) () -> Bool

    public enum LoadError: Error, CustomStringConvertible {
        case open(String)
        case missing(String)
        case notLoaded

        public var description: String {
            switch self {
            case .open(let message): "could not open libCKivyNUI: \(message)"
            case .missing(let symbol): "libCKivyNUI has no \(symbol)"
            case .notLoaded: "libCKivyNUI is not loaded: import one of Kivy's nui modules first"
            }
        }
    }

    /// The libCKivyNUI Kivy's extensions loaded — after Python has imported
    /// one of them (`kivy.graphics.ngl_backend.ngl_nui`). Whichever file
    /// their rpath found, the host registers with that one.
    public static func loadedByKivy() throws -> KivyNUILibrary {
        if let linked = linkedIntoTheApp() { return linked }
        for name in ["libCKivyNUI.dylib", "libCKivyNUI.so"] {
            if let path = LoadedLibraries().path(named: name) { return try load(path: path) }
        }
        throw LoadError.notLoaded
    }

    /// `path`, else `$KIVY_NUI_LIB`, else `libCKivyNUI` on the loader's
    /// search path (next to the executable, through its rpaths).
    public static func load(path: String? = nil) throws -> KivyNUILibrary {
        let environment = ProcessInfo.processInfo.environment["KIVY_NUI_LIB"]
        #if os(macOS) || os(iOS)
        let fallback = "libCKivyNUI.dylib"
        #else
        let fallback = "libCKivyNUI.so"
        #endif
        return try open(path ?? environment ?? fallback)
    }
}
