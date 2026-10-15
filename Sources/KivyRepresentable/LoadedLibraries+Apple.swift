//
//  LoadedLibraries+Apple.swift
//  KivyRepresentable
//

#if os(macOS) || os(iOS)
import Darwin
import MachO

extension LoadedLibraries {
    static func platformPath(named fileName: String) -> String? {
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            let path = String(cString: name)
            if path.hasSuffix("/" + fileName) { return path }
        }
        return nil
    }

    static func platformPath(definingSymbol symbol: String) -> String? {
        // RTLD_DEFAULT is ((void *)-2) on Darwin; the macro doesn't import.
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { return nil }
        var info = Dl_info()
        guard dladdr(address, &info) != 0, let name = info.dli_fname else { return nil }
        return String(cString: name)
    }
}
#endif
