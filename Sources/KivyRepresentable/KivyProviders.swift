//
//  KivyProviders.swift
//  KivyRepresentable
//
//  What Kivy's `nui` text and image providers ask the host for: text
//  measured and drawn, images decoded and drawn, with Skia straight into the
//  texture Kivy made (KivyGL+Skia.swift). Kivy's canvas then draws that
//  texture as it draws any other.
//
//  Text is drawn the way Kivy's SDL2 provider lays it out: each run's line
//  box starts at its (x, y), the baseline one ascent below, an outline
//  grows the box by its width on every side.
//

import CKivyNUI
import NucleantSkia

public final class KivyProviders {

    /// Typefaces by font file: Kivy names fonts by their file.
    private var typefaces: [String: SkTypeface] = [:]

    public init() {}

    // MARK: - Text

    private func font(_ spec: KivyNUIFont) -> SkFont? {
        guard let path = spec.path.map({ String(cString: $0) }), spec.size >= 1 else { return nil }
        let typeface: SkTypeface
        if let cached = typefaces[path] {
            typeface = cached
        } else {
            guard let made = SkFontMgr.makeFromFile(path) else { return nil }
            typefaces[path] = made
            typeface = made
        }
        let font = SkFont(typeface, size: spec.size)
        font.setEdging(spec.antialias ? .antiAlias : .alias)
        switch spec.hinting {
        case 0: font.setHinting(.none)
        case 1: font.setHinting(.slight)
        case 3: font.setHinting(.full)
        default: font.setHinting(.normal)
        }
        return font
    }

    private static func ascentDescent(_ font: SkFont) -> (ascent: Float, descent: Float) {
        let metrics = font.getMetrics()
        return ((-metrics.ascent).rounded(.up), metrics.descent.rounded(.up))
    }

    /// Advance width and line height, an outline's width added each side.
    public func extents(_ spec: KivyNUIFont, _ text: String) -> (width: Int32, height: Int32)? {
        guard let font = font(spec) else { return nil }
        let (ascent, descent) = Self.ascentDescent(font)
        let outline = 2 * spec.outline_width.rounded()
        return (Int32(font.measureText(text).rounded(.up) + outline), Int32(ascent + descent + outline))
    }

    public func metrics(_ spec: KivyNUIFont) -> (ascent: Int32, descent: Int32)? {
        guard let font = font(spec) else { return nil }
        let (ascent, descent) = Self.ascentDescent(font)
        return (Int32(ascent), Int32(descent))
    }

    /// Clears texture `name` and draws `runs` into it.
    public func drawText(_ runs: UnsafeBufferPointer<KivyNUITextRun>, texture name: KivyNUIGLuint, width: Int, height: Int, gl: KivyGL) throws {
        try gl.fillWithSkia(texture: name, width: width, height: height) { canvas in
            for run in runs {
                guard let utf8 = run.utf8, let font = font(run.font) else { continue }
                let text = String(cString: utf8)
                let (ascent, _) = Self.ascentDescent(font)
                let outline = run.font.outline_width.rounded()
                let x = run.x + outline
                let baseline = run.y + outline + ascent
                let color = SIMD4(run.color.0, run.color.1, run.color.2, run.color.3)

                if outline > 0 {
                    // Kivy's SDL2 provider: the outline in its own color at
                    // the text's alpha, the text over it.
                    let paint = SkPaint(color: SIMD4(run.outline_color.0, run.outline_color.1, run.outline_color.2, color.w))
                    paint.setStyle(.strokeAndFill)
                    paint.setStrokeWidth(2 * outline)
                    paint.setStrokeJoin(.round)
                    paint.setAntiAlias(run.font.antialias)
                    canvas.drawString(text, x: x, y: baseline, font: font, paint: paint)
                }
                let paint = SkPaint(color: color)
                paint.setAntiAlias(run.font.antialias)
                canvas.drawString(text, x: x, y: baseline, font: font, paint: paint)

                if run.font.underline || run.font.strikethrough {
                    let metrics = font.getMetrics()
                    let advance = font.measureText(text)
                    // Whole rows, as SDL2_ttf draws them.
                    func bar(at position: Float, thickness: Float) {
                        let rect = SkPaint(color: color)
                        rect.setAntiAlias(false)
                        canvas.drawRect(x: x, y: (baseline + position).rounded(), w: advance,
                                        h: max(1, thickness.rounded()), paint: rect)
                    }
                    if run.font.underline {
                        let thickness = metrics.flags & 1 != 0 ? metrics.underlineThickness : max(1, run.font.size / 14)
                        let position = metrics.flags & 2 != 0 ? metrics.underlinePosition : thickness
                        bar(at: position, thickness: thickness)
                    }
                    if run.font.strikethrough {
                        let thickness = metrics.flags & 4 != 0 ? metrics.strikeoutThickness : max(1, run.font.size / 14)
                        let position = metrics.flags & 8 != 0 ? metrics.strikeoutPosition : -ascent * 0.3
                        bar(at: position, thickness: thickness)
                    }
                }
            }
        }
    }

    // MARK: - Images

    /// A raster image (PNG, JPEG, WebP, ...) or, when no codec reads it, an
    /// SVG document at its own size: the root's width and height, or its
    /// viewBox's when those are in percent (as SDL_image sized them).
    private enum Decoded {
        case raster(SkCodec)
        case svg(SkSVGDOM, size: SIMD2<Int32>)

        init?(_ data: UnsafeRawBufferPointer) {
            if let codec = SkCodec.makeFromData(data) {
                self = .raster(codec)
                return
            }
            guard let dom = SkSVGDOM.make(data) else { return nil }
            var size = dom.intrinsicSize()
            if size.x <= 0 || size.y <= 0, let box = dom.viewBox() { size = box.size }
            let pixels = SIMD2<Int32>(size.rounded(.up))
            guard pixels.x > 0, pixels.y > 0 else { return nil }
            dom.setContainerSize(SIMD2<Float>(pixels))
            self = .svg(dom, size: pixels)
        }

        var size: SIMD2<Int32> {
            switch self {
            case .raster(let codec): return codec.size()
            case .svg(_, let size): return size
            }
        }
    }

    public func imageSize(_ data: UnsafeRawBufferPointer) -> (width: Int32, height: Int32)? {
        guard let decoded = Decoded(data) else { return nil }
        return (decoded.size.x, decoded.size.y)
    }

    /// Decodes `data` and draws it at the top-left of texture `name`.
    public func drawImage(_ data: UnsafeRawBufferPointer, texture name: KivyNUIGLuint, width: Int, height: Int, gl: KivyGL) throws -> Bool {
        switch Decoded(data) {
        case .raster(let codec):
            guard let pixels = codec.getPixels(),
                  let image = SkImages.rasterFromPixmapCopy(pixels, size: codec.size())
            else { return false }
            try gl.fillWithSkia(texture: name, width: width, height: height) { canvas in
                canvas.drawImage(image, pos: .zero)
            }
        case .svg(let dom, _):
            try gl.fillWithSkia(texture: name, width: width, height: height) { canvas in
                dom.render(canvas)
            }
        case nil:
            return false
        }
        return true
    }

    /// Decoded RGBA, straight alpha, first row first.
    public func imagePixels(_ data: UnsafeRawBufferPointer, into out: UnsafeMutableRawBufferPointer) -> Bool {
        guard let decoded = Decoded(data), out.count == Int(decoded.size.x) * Int(decoded.size.y) * 4 else { return false }
        let pixels: [UInt8]
        switch decoded {
        case .raster(let codec):
            guard let decoded = codec.getPixels(colorType: .rgba8888, alphaType: .unpremul) else { return false }
            decoded.withUnsafeBytes { out.copyMemory(from: $0) }
            return true
        case .svg(let dom, let size):
            guard let surface = SkSurfaces.raster(width: size.x, height: size.y) else { return false }
            dom.render(surface.getCanvas())
            pixels = surface.readPixels()
        }
        guard pixels.count == out.count else { return false }
        pixels.withUnsafeBytes { out.copyMemory(from: $0) }
        return true
    }
}
