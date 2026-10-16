//
//  PageReload+Wasm.swift
//  WebPlayground
//
//  The page's editors changed: it calls `kivy_playground_reload`, which reads
//  their sources through the page's imports and hands them to the runner
//  (kivy_playground.runner.reload), in the app's Python.
//

#if os(WASI)
import CPython
import CKivyPlaygroundPage

@_expose(wasm, "kivy_playground_reload")
public func kivyPlaygroundReload() {
    let py = pageSource(0)
    let kv = pageSource(1)
    let gil = PyGILState_Ensure()
    defer { PyGILState_Release(gil) }
    guard let runner = PyImport_ImportModule("kivy_playground.runner") else {
        PyErr_Print()
        return
    }
    defer { Py_DecRef(runner) }
    guard let reload = PyObject_GetAttrString(runner, "reload") else {
        PyErr_Print()
        return
    }
    defer { Py_DecRef(reload) }
    let arguments = PyTuple_New(2)
    defer { Py_DecRef(arguments) }
    // PyTuple_SetItem takes the strings' references.
    PyTuple_SetItem(arguments, 0, PyUnicode_FromString(py))
    PyTuple_SetItem(arguments, 1, PyUnicode_FromString(kv))
    if let result = PyObject_CallObject(reload, arguments) {
        Py_DecRef(result)
    } else {
        PyErr_Print()
    }
}

/// One of the page's sources: 0 app.py, 1 app.kv.
private func pageSource(_ which: Int32) -> String {
    let length = Int(kivy_playground_source_length(which))
    var bytes = [CChar](repeating: 0, count: length + 1)
    bytes.withUnsafeMutableBufferPointer { kivy_playground_source_copy(which, $0.baseAddress) }
    return String(cString: bytes)
}
#endif
