//
//  LoadedLibraries+Linux.swift
//  KivyRepresentable
//
//  Not done yet on Linux and Android (dl_iterate_phdr / dladdr): nothing is
//  found, so starting Kivy there fails with "could not find the Python home"
//  or "libCKivyNUI is not loaded" rather than guessing.
//

#if os(Linux) || os(Android)
extension LoadedLibraries {
    static func platformPath(named fileName: String) -> String? { nil }
    static func platformPath(definingSymbol symbol: String) -> String? { nil }
}
#endif
