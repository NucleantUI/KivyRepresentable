//
//  PythonLayout.swift
//  KivyRepresentable
//
//  Where the Python this app runs keeps its standard library, and what it
//  shares with the app: KivyLauncher's platform part. Each platform answers
//  in its own file.
//

final class PythonLayout {
    /// PYTHONHOME, when the launcher isn't given one.
    func home() -> String? {
        platformHome()
    }

    /// The standard library's folders (and archives) under `home`, the
    /// module search path before the app's site-packages.
    func standardLibrary(home: String) -> [String] {
        platformStandardLibrary(home: home)
    }

    /// The app's environment, when Python's starts without it and gets a
    /// copy once running; nil where they are one.
    func environmentToCopy() -> [String: String]? {
        platformEnvironmentToCopy()
    }
}
