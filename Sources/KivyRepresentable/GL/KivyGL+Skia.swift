//
//  KivyGL+Skia.swift
//  KivyRepresentable
//
//  Skia drawing straight into a GL texture. The texture's VkImage is
//  wrapped as a Skia surface, the way NucleantSkia's node wraps the image it
//  renders into, so what Skia draws is what Kivy samples: no pixels go
//  through the CPU, and nothing Kivy does with the texture changes.
//
//  Skia records on its own command buffers and submits on the same queue as
//  the GL frame. Kivy's recorded work is submitted before Skia's, and Skia
//  leaves the image as a color attachment, which the GL frame's own barrier
//  takes it from on the next draw that samples it.
//

@preconcurrency import CVulkan
import CKivyNUI
import NucleantSkia

public enum KivySkiaError: Error {
    /// No texture by that name, or one with no storage yet.
    case noTexture(KivyNUIGLuint)
    /// Skia wraps one level; a texture after glGenerateMipmap has more.
    case mipmapped(KivyNUIGLuint)
    /// Skia didn't take the image or didn't submit.
    case surface
    case flush
}

extension KivyGL {

    /// Draws with Skia into texture `name` as it is now: over its pixels,
    /// which stay its pixels for Kivy.
    ///
    /// The canvas is the texture's pixel rows, first row at the top, which
    /// is the order Kivy's image data comes in. A texture Kivy flips for
    /// that (`Texture.flip_vertical()`, as it does for its images and text)
    /// shows upright. The canvas starts with no matrix or clip each call.
    public func drawWithSkia(texture name: KivyNUIGLuint, _ draw: (SkCanvas) throws -> Void) throws {
        guard let image = textures[name]?.image else { throw KivySkiaError.noTexture(name) }
        guard image.levels == 1 else { throw KivySkiaError.mipmapped(name) }
        let surface = try skiaSurface(for: image)
        guard let canvas = surface.canvas else { throw KivySkiaError.surface }

        // Everything Kivy recorded so far (an upload into this texture, a
        // pass rendering into it) is on the queue ahead of Skia's work.
        frame.submit()
        surface.notifyLayout(image.layout.rawValue)

        let saved = canvas.save()
        defer { canvas.restoreToCount(saved) }
        try draw(canvas)

        guard surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue) else {
            throw KivySkiaError.flush
        }
        image.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    }

    /// Draws with Skia the whole of texture `name` anew, from transparent:
    /// what the text and image providers do with a label's or an image's
    /// texture. A texture with no storage yet gets it at `width` x `height`,
    /// as glTexImage2D without pixels would give it. A mipmapped one gets a
    /// single level for Skia and its mipmaps made again after.
    public func fillWithSkia(texture name: KivyNUIGLuint, width: Int, height: Int, _ draw: (SkCanvas) throws -> Void) throws {
        guard let texture = textures[name] else { throw KivySkiaError.noTexture(name) }
        let mipmapped = (texture.image?.levels ?? 1) > 1
        if texture.image == nil || mipmapped {
            let width = texture.image?.width ?? width, height = texture.image?.height ?? height
            guard width > 0, height > 0, width <= Self.maxTextureSize, height <= Self.maxTextureSize else {
                throw KivySkiaError.noTexture(name)
            }
            if let old = texture.image { frame.retire { old.destroy() } }
            texture.image = try GLImage(
                device: device, width: width, height: height, format: Self.colorFormat,
                usage: Self.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            )
        }
        try drawWithSkia(texture: name) { canvas in
            canvas.clear(SIMD4<Float>(0, 0, 0, 0))
            try draw(canvas)
        }
        if mipmapped { makeMipmaps(of: texture) }
    }

    /// The image's surface, made the first time Skia draws into it.
    private func skiaSurface(for image: GLImage) throws -> SkiaSurface {
        if let surface = image.skiaSurface { return surface }
        let context = try skiaContext ?? device.makeSkiaContext()
        skiaContext = context
        let surface = try SkiaSurface(
            context: context,
            vkImage: image.image,
            width: image.width,
            height: image.height,
            format: image.format.rawValue,
            layout: image.layout.rawValue,
            usageFlags: UInt32(Self.colorUsage),
            queueFamilyIndex: device.queueFamilyIndex
        )
        image.skiaSurface = surface
        return surface
    }
}
