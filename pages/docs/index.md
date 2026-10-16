# KivyRepresentable

Kivy apps inside [NucleantUI](https://github.com/NucleantUI/NucleantUI) apps.
Kivy draws through KivyRepresentable's GL on NucleantVulkan, and the app's
own Python runs it: on macOS, and in the browser on WebGPU with Pyodide's
Python.

Try it in the [Playground](playground.md): edit `app.kv` and `app.py`, and
the Kivy app beside them runs again.

## A Kivy app in a window

```swift
import KivyRepresentable

@main
struct MyApp: KivyApp {
    var site_packages: String { ... } // Kivy and your app, installed with uv pip install --target

    var body: some Scene {
        KivyWindowGroup("My Kivy App", module: "myapp")
    }
}
```

`module` runs as `__main__`, as `python -m myapp` would.

## A Kivy app in a view

```swift
WindowGroup("Editor") {
    HStack {
        Sidebar()
        KivyAppView(module: "myapp")
    }
}
```

`KivyAppView` fills the space it is offered, next to any other NucleantUI
views; the playground is one, filling its window. Kivy runs once per
process, so every `KivyAppView` shows the same Kivy app.
