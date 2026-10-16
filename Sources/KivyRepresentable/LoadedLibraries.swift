//
//  LoadedLibraries.swift
//  KivyRepresentable
//
//  Which shared libraries this process has loaded: where the linked Python
//  lives, and which libCKivyNUI Kivy's extensions loaded — the one the host
//  has to register with. Each platform answers in its own file.
//

final class LoadedLibraries {
    /// The file of the loaded library named `fileName` (e.g.
    /// "libCKivyNUI.dylib"), if one is loaded.
    func path(named fileName: String) -> String? {
        platformPath(named: fileName)
    }

    /// The file of the library that defines `symbol`.
    func path(definingSymbol symbol: String) -> String? {
        platformPath(definingSymbol: symbol)
    }
}
