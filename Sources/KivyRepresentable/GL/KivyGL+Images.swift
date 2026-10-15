//
//  KivyGL+Images.swift
//  KivyRepresentable
//
//  Textures, renderbuffers and framebuffers, and the calls that write or
//  read their pixels: glTexImage2D and friends, glClear, glReadPixels, and
//  `present`, which hands framebuffer 0 to the shader node.
//
//  Every color image is RGBA8. GL's other upload formats (RGB, BGRA,
//  luminance, alpha, ...) are converted on the way in, which keeps sampling,
//  rendering into a texture (Kivy's Fbo) and reading back the same for all
//  of them.
//

@preconcurrency import CVulkan

extension KivyGL {

    // MARK: - Textures

    func texImage2D(
        _ target: GLenum, _ level: GLint, _ internalFormat: GLint, _ width: GLsizei, _ height: GLsizei,
        _ border: GLint, _ format: GLenum, _ type: GLenum, _ pixels: UnsafeRawPointer?
    ) {
        guard target == GL.texture2D else { return setError(GL.invalidEnum) }
        guard let texture = boundTexture else { return setError(GL.invalidOperation) }
        guard width >= 0, height >= 0, level >= 0, border == 0,
              Int(width) <= Self.maxTextureSize, Int(height) <= Self.maxTextureSize
        else { return setError(GL.invalidValue) }
        let width = Int(width), height = Int(height), level = Int(level)

        if level > 0 {
            // Only into a chain glGenerateMipmap made.
            guard let image = texture.image, level < image.levels,
                  width == max(1, image.width >> level), height == max(1, image.height >> level)
            else { return }
            if let pixels, let rgba = unpackRGBA(pixels, width: width, height: height, format: format, type: type) {
                upload(rgba, to: image, level: level, x: 0, y: 0, width: width, height: height)
            }
            return
        }

        texture.internalFormat = GLenum(internalFormat)
        if width == 0 || height == 0 {
            if let image = texture.image { frame.retire { image.destroy() } }
            texture.image = nil
            return
        }
        if texture.image == nil || texture.image!.width != width || texture.image!.height != height || texture.image!.levels != 1 {
            if let image = texture.image { frame.retire { image.destroy() } }
            do {
                texture.image = try GLImage(
                    device: device, width: width, height: height, format: Self.colorFormat,
                    usage: Self.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
                )
            } catch {
                texture.image = nil
                return setError(GL.outOfMemory)
            }
        }
        let image = texture.image!
        if let pixels {
            guard let rgba = unpackRGBA(pixels, width: width, height: height, format: format, type: type) else {
                return setError(GL.invalidEnum)
            }
            upload(rgba, to: image, level: 0, x: 0, y: 0, width: width, height: height)
        } else {
            clearToTransparent(image)
        }
    }

    func texSubImage2D(
        _ target: GLenum, _ level: GLint, _ x: GLint, _ y: GLint, _ width: GLsizei, _ height: GLsizei,
        _ format: GLenum, _ type: GLenum, _ pixels: UnsafeRawPointer?
    ) {
        guard target == GL.texture2D else { return setError(GL.invalidEnum) }
        guard let image = boundTexture?.image, Int(level) < image.levels else { return setError(GL.invalidOperation) }
        let levelWidth = max(1, image.width >> Int(level)), levelHeight = max(1, image.height >> Int(level))
        guard x >= 0, y >= 0, width >= 0, height >= 0,
              Int(x) + Int(width) <= levelWidth, Int(y) + Int(height) <= levelHeight
        else { return setError(GL.invalidValue) }
        guard let pixels, width > 0, height > 0 else { return }
        guard let rgba = unpackRGBA(pixels, width: Int(width), height: Int(height), format: format, type: type) else {
            return setError(GL.invalidEnum)
        }
        upload(rgba, to: image, level: Int(level), x: Int(x), y: Int(y), width: Int(width), height: Int(height))
    }

    func texParameter(_ target: GLenum, _ pname: GLenum, _ value: GLint) {
        guard target == GL.texture2D else { return setError(GL.invalidEnum) }
        guard let texture = boundTexture else { return setError(GL.invalidOperation) }
        let value = GLenum(bitPattern: value)
        switch pname {
        case GL.textureMinFilter: texture.minFilter = value
        case GL.textureMagFilter: texture.magFilter = value
        case GL.textureWrapS: texture.wrapS = value
        case GL.textureWrapT: texture.wrapT = value
        default: setError(GL.invalidEnum)
        }
    }

    func getTexParameter(_ target: GLenum, _ pname: GLenum) -> GLint? {
        guard target == GL.texture2D, let texture = boundTexture else {
            setError(GL.invalidEnum)
            return nil
        }
        switch pname {
        case GL.textureMinFilter: return GLint(texture.minFilter)
        case GL.textureMagFilter: return GLint(texture.magFilter)
        case GL.textureWrapS: return GLint(texture.wrapS)
        case GL.textureWrapT: return GLint(texture.wrapT)
        default:
            setError(GL.invalidEnum)
            return nil
        }
    }

    func generateMipmap(_ target: GLenum) {
        guard target == GL.texture2D else { return setError(GL.invalidEnum) }
        guard let texture = boundTexture, let source = texture.image else { return setError(GL.invalidOperation) }
        var levels = 1
        while max(source.width, source.height) >> levels > 0 { levels += 1 }
        guard levels > 1 else { return }

        let image: GLImage
        if source.levels == levels {
            image = source
        } else {
            do {
                image = try GLImage(
                    device: device, width: source.width, height: source.height, format: Self.colorFormat,
                    levels: levels, usage: Self.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
                )
            } catch {
                return setError(GL.outOfMemory)
            }
        }
        frame.endPass()
        let cmd = frame.begin()
        if image !== source {
            frame.transition(source, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
            frame.transition(image, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
            var region = VkImageCopy()
            region.srcSubresource = Self.colorLayers(level: 0)
            region.dstSubresource = Self.colorLayers(level: 0)
            region.extent = VkExtent3D(width: UInt32(source.width), height: UInt32(source.height), depth: 1)
            vkCmdCopyImage(cmd, source.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region)
            frame.retire { source.destroy() }
            texture.image = image
        } else {
            frame.transition(image, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
        }
        // Each level from the one above it: that one goes to TRANSFER_SRC,
        // the rest of the chain stays TRANSFER_DST.
        for level in 1..<levels {
            levelBarrier(cmd, image, level: level - 1,
                         from: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
            var blit = VkImageBlit()
            blit.srcSubresource = Self.colorLayers(level: level - 1)
            blit.dstSubresource = Self.colorLayers(level: level)
            blit.srcOffsets.1 = VkOffset3D(x: Int32(max(1, image.width >> (level - 1))), y: Int32(max(1, image.height >> (level - 1))), z: 1)
            blit.dstOffsets.1 = VkOffset3D(x: Int32(max(1, image.width >> level)), y: Int32(max(1, image.height >> level)), z: 1)
            vkCmdBlitImage(cmd, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR)
        }
        // The last level is still TRANSFER_DST; bring it level with the rest.
        levelBarrier(cmd, image, level: levels - 1,
                     from: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
        image.layout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
    }

    private func levelBarrier(_ cmd: VkCommandBuffer, _ image: GLImage, level: Int, from: VkImageLayout, to: VkImageLayout) {
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.srcAccessMask = VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
        barrier.dstAccessMask = VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue)
        barrier.oldLayout = from
        barrier.newLayout = to
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image.image
        barrier.subresourceRange = VkImageSubresourceRange(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel: UInt32(level), levelCount: 1, baseArrayLayer: 0, layerCount: 1
        )
        let stage = VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        vkCmdPipelineBarrier(cmd, stage, stage, 0, 0, nil, 0, nil, 1, &barrier)
    }

    static func colorLayers(level: Int) -> VkImageSubresourceLayers {
        VkImageSubresourceLayers(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            mipLevel: UInt32(level), baseArrayLayer: 0, layerCount: 1
        )
    }

    /// Tightly packed RGBA8 rows into `image`, recorded in the frame.
    func upload(_ rgba: [UInt8], to image: GLImage, level: Int, x: Int, y: Int, width: Int, height: Int) {
        guard let staging = try? rgba.withUnsafeBytes({ try frame.arena.upload($0, alignment: 4) }) else {
            return setError(GL.outOfMemory)
        }
        frame.endPass()
        let cmd = frame.begin()
        frame.transition(image, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
        var region = VkBufferImageCopy()
        region.bufferOffset = VkDeviceSize(staging.offset)
        region.imageSubresource = Self.colorLayers(level: level)
        region.imageOffset = VkOffset3D(x: Int32(x), y: Int32(y), z: 0)
        region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        vkCmdCopyBufferToImage(cmd, staging.buffer, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region)
    }

    /// A texture specified without pixels starts transparent black rather
    /// than with whatever the allocation held.
    private func clearToTransparent(_ image: GLImage) {
        frame.endPass()
        let cmd = frame.begin()
        frame.transition(image, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
        var color = VkClearColorValue(float32: (0, 0, 0, 0))
        var range = VkImageSubresourceRange(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel: 0, levelCount: UInt32(image.levels), baseArrayLayer: 0, layerCount: 1
        )
        vkCmdClearColorImage(cmd, image.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range)
    }

    // MARK: - Pixel formats

    /// GL client pixels, as glTexImage2D reads them (unpack alignment and
    /// row length included), as tightly packed RGBA8. Nil for a format/type
    /// pair GLES2 doesn't have.
    func unpackRGBA(_ pixels: UnsafeRawPointer, width: Int, height: Int, format: GLenum, type: GLenum) -> [UInt8]? {
        let bytesPerPixel: Int
        switch (format, type) {
        case (GL.rgba, GL.unsignedByte), (GL.bgra, GL.unsignedByte): bytesPerPixel = 4
        case (GL.rgb, GL.unsignedByte), (GL.bgr, GL.unsignedByte): bytesPerPixel = 3
        case (GL.luminanceAlpha, GL.unsignedByte), (GL.rg, GL.unsignedByte): bytesPerPixel = 2
        case (GL.luminance, GL.unsignedByte), (GL.alpha, GL.unsignedByte), (GL.red, GL.unsignedByte): bytesPerPixel = 1
        case (GL.rgb, GL.unsignedShort565), (GL.rgba, GL.unsignedShort4444), (GL.rgba, GL.unsignedShort5551): bytesPerPixel = 2
        default: return nil
        }
        let rowPixels = unpackRowLength > 0 ? unpackRowLength : width
        let rowBytes = (rowPixels * bytesPerPixel + unpackAlignment - 1) / unpackAlignment * unpackAlignment
        let source = pixels.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        out.withUnsafeMutableBufferPointer { dst in
            for row in 0..<height {
                let s = source + row * rowBytes
                let d = dst.baseAddress! + row * width * 4
                switch (format, type) {
                case (GL.rgba, GL.unsignedByte):
                    d.update(from: s, count: width * 4)
                case (GL.bgra, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i * 4 + 2]; d[i * 4 + 1] = s[i * 4 + 1]; d[i * 4 + 2] = s[i * 4]; d[i * 4 + 3] = s[i * 4 + 3]
                    }
                case (GL.rgb, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i * 3]; d[i * 4 + 1] = s[i * 3 + 1]; d[i * 4 + 2] = s[i * 3 + 2]
                    }
                case (GL.bgr, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i * 3 + 2]; d[i * 4 + 1] = s[i * 3 + 1]; d[i * 4 + 2] = s[i * 3]
                    }
                case (GL.luminance, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i]; d[i * 4 + 1] = s[i]; d[i * 4 + 2] = s[i]
                    }
                case (GL.red, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i]; d[i * 4 + 1] = 0; d[i * 4 + 2] = 0
                    }
                case (GL.alpha, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = 0; d[i * 4 + 1] = 0; d[i * 4 + 2] = 0; d[i * 4 + 3] = s[i]
                    }
                case (GL.luminanceAlpha, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i * 2]; d[i * 4 + 1] = s[i * 2]; d[i * 4 + 2] = s[i * 2]; d[i * 4 + 3] = s[i * 2 + 1]
                    }
                case (GL.rg, GL.unsignedByte):
                    for i in 0..<width {
                        d[i * 4] = s[i * 2]; d[i * 4 + 1] = s[i * 2 + 1]; d[i * 4 + 2] = 0
                    }
                default:
                    let shorts = UnsafeRawPointer(s)
                    for i in 0..<width {
                        let v = shorts.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)
                        let (r, g, b, a): (UInt16, UInt16, UInt16, UInt16)
                        switch type {
                        case GL.unsignedShort565:
                            (r, g, b, a) = ((v >> 11) * 255 / 31, ((v >> 5) & 63) * 255 / 63, (v & 31) * 255 / 31, 255)
                        case GL.unsignedShort4444:
                            (r, g, b, a) = ((v >> 12) * 17, ((v >> 8) & 15) * 17, ((v >> 4) & 15) * 17, (v & 15) * 17)
                        default:
                            (r, g, b, a) = ((v >> 11) * 255 / 31, ((v >> 6) & 31) * 255 / 31, ((v >> 1) & 31) * 255 / 31, (v & 1) * 255)
                        }
                        d[i * 4] = UInt8(r); d[i * 4 + 1] = UInt8(g); d[i * 4 + 2] = UInt8(b); d[i * 4 + 3] = UInt8(a)
                    }
                }
            }
        }
        return out
    }

    // MARK: - Samplers

    func sampler(for texture: GLTexture, levels: Int) -> VkSampler? {
        let key = "\(texture.minFilter)-\(texture.magFilter)-\(texture.wrapS)-\(texture.wrapT)-\(levels)"
        if let sampler = samplers[key] { return sampler }
        func filter(_ value: GLenum) -> VkFilter {
            switch value {
            case GL.nearest, GL.nearestMipmapNearest, GL.nearestMipmapLinear: VK_FILTER_NEAREST
            default: VK_FILTER_LINEAR
            }
        }
        func wrap(_ value: GLenum) -> VkSamplerAddressMode {
            switch value {
            case GL.clampToEdge: VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
            case GL.mirroredRepeat: VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT
            default: VK_SAMPLER_ADDRESS_MODE_REPEAT
            }
        }
        let mipmapped = [GL.nearestMipmapNearest, GL.linearMipmapNearest, GL.nearestMipmapLinear, GL.linearMipmapLinear]
            .contains(texture.minFilter)
        var info = VkSamplerCreateInfo()
        info.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
        info.magFilter = filter(texture.magFilter)
        info.minFilter = filter(texture.minFilter)
        info.mipmapMode = [GL.nearestMipmapLinear, GL.linearMipmapLinear].contains(texture.minFilter)
            ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST
        info.addressModeU = wrap(texture.wrapS)
        info.addressModeV = wrap(texture.wrapT)
        info.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT
        info.minLod = 0
        // Without mipmap filtering, or without a chain, GL samples level 0.
        // Vulkan picks min vs mag filter after clamping the LOD, so a cap of
        // 0 would always magnify; 0.25 still minifies, and nearest mip
        // selection rounds it to level 0 (ANGLE does the same).
        info.maxLod = mipmapped ? Float(levels - 1) : 0.25
        if !mipmapped { info.mipmapMode = VK_SAMPLER_MIPMAP_MODE_NEAREST }
        var sampler: VkSampler?
        guard vkCreateSampler(device.device, &info, nil, &sampler) == VK_SUCCESS, let sampler else { return nil }
        samplers[key] = sampler
        return sampler
    }

    /// What an unbound or unspecified texture samples: GL's incomplete
    /// texture, opaque black.
    func blankTexture() -> GLImage? {
        if let blank = blankImage { return blank }
        guard let image = try? GLImage(
            device: device, width: 1, height: 1, format: Self.colorFormat,
            usage: Self.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
        ) else { return nil }
        upload([0, 0, 0, 255], to: image, level: 0, x: 0, y: 0, width: 1, height: 1)
        blankImage = image
        return image
    }

    // MARK: - Renderbuffers

    func renderbufferStorage(_ target: GLenum, _ internalFormat: GLenum, _ width: GLsizei, _ height: GLsizei) {
        guard target == GL.renderbuffer else { return setError(GL.invalidEnum) }
        guard let renderbuffer = renderbuffers[boundRenderbuffer] else { return setError(GL.invalidOperation) }
        guard width >= 0, height >= 0, Int(width) <= Self.maxTextureSize, Int(height) <= Self.maxTextureSize else {
            return setError(GL.invalidValue)
        }
        if let image = renderbuffer.image { frame.retire { image.destroy() } }
        renderbuffer.image = nil
        renderbuffer.internalFormat = internalFormat
        guard width > 0, height > 0 else { return }
        do {
            switch internalFormat {
            case GL.depthComponent16, GL.stencilIndex8, GL.depth24Stencil8Oes:
                renderbuffer.image = try makeDepthStencilImage(width: Int(width), height: Int(height))
            case GL.rgba4, GL.rgb565, GL.rgb5A1, GL.rgba8, GL.rgb8:
                renderbuffer.image = try GLImage(
                    device: device, width: Int(width), height: Int(height), format: Self.colorFormat,
                    usage: Self.colorUsage, aspect: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
                )
            default:
                setError(GL.invalidEnum)
            }
        } catch {
            setError(GL.outOfMemory)
        }
    }

    func getRenderbufferParameter(_ pname: GLenum) -> GLint? {
        guard let renderbuffer = renderbuffers[boundRenderbuffer] else {
            setError(GL.invalidOperation)
            return nil
        }
        let depthStencil = renderbuffer.image?.isDepthStencil ?? false
        switch pname {
        case GL.renderbufferWidth: return GLint(renderbuffer.image?.width ?? 0)
        case GL.renderbufferHeight: return GLint(renderbuffer.image?.height ?? 0)
        case GL.renderbufferInternalFormat: return GLint(renderbuffer.internalFormat)
        case GL.renderbufferRedSize, GL.renderbufferGreenSize, GL.renderbufferBlueSize, GL.renderbufferAlphaSize:
            return depthStencil || renderbuffer.image == nil ? 0 : 8
        case GL.renderbufferDepthSize: return depthStencil ? 24 : 0
        case GL.renderbufferStencilSize: return depthStencil ? 8 : 0
        default:
            setError(GL.invalidEnum)
            return nil
        }
    }

    // MARK: - Framebuffers

    func framebufferTexture2D(_ target: GLenum, _ attachment: GLenum, _ textureTarget: GLenum, _ texture: GLuint, _ level: GLint) {
        guard target == GL.framebuffer else { return setError(GL.invalidEnum) }
        guard let framebuffer = framebuffers[boundFramebuffer] else { return setError(GL.invalidOperation) }
        guard texture == 0 || textureTarget == GL.texture2D else { return setError(GL.invalidEnum) }
        let value: GLFramebuffer.Attachment? = texture == 0 ? nil : .texture(texture)
        switch attachment {
        case GL.colorAttachment0: framebuffer.color = value
        case GL.depthAttachment: framebuffer.depth = value
        case GL.stencilAttachment: framebuffer.stencil = value
        default: setError(GL.invalidEnum)
        }
    }

    func framebufferRenderbuffer(_ target: GLenum, _ attachment: GLenum, _ renderbufferTarget: GLenum, _ renderbuffer: GLuint) {
        guard target == GL.framebuffer else { return setError(GL.invalidEnum) }
        guard let framebuffer = framebuffers[boundFramebuffer] else { return setError(GL.invalidOperation) }
        let value: GLFramebuffer.Attachment? = renderbuffer == 0 ? nil : .renderbuffer(renderbuffer)
        switch attachment {
        case GL.colorAttachment0: framebuffer.color = value
        case GL.depthAttachment: framebuffer.depth = value
        case GL.stencilAttachment: framebuffer.stencil = value
        case GL.depthStencilAttachment:
            framebuffer.depth = value
            framebuffer.stencil = value
        default: setError(GL.invalidEnum)
        }
    }

    func getFramebufferAttachmentParameter(_ attachment: GLenum, _ pname: GLenum) -> GLint? {
        guard let framebuffer = framebuffers[boundFramebuffer] else {
            setError(GL.invalidOperation)
            return nil
        }
        let value: GLFramebuffer.Attachment?
        switch attachment {
        case GL.colorAttachment0: value = framebuffer.color
        case GL.depthAttachment: value = framebuffer.depth
        case GL.stencilAttachment: value = framebuffer.stencil
        default:
            setError(GL.invalidEnum)
            return nil
        }
        switch pname {
        case GL.framebufferAttachmentObjectType:
            switch value {
            case .texture: return GLint(GL.texture)
            case .renderbuffer: return GLint(GL.renderbuffer)
            case nil: return GLint(GL.`none`)
            }
        case GL.framebufferAttachmentObjectName:
            switch value {
            case .texture(let name), .renderbuffer(let name): return GLint(name)
            case nil: return 0
            }
        case GL.framebufferAttachmentTextureLevel, GL.framebufferAttachmentTextureCubeMapFace:
            return 0
        default:
            setError(GL.invalidEnum)
            return nil
        }
    }

    private func image(of attachment: GLFramebuffer.Attachment?) -> GLImage? {
        switch attachment {
        case .texture(let name): textures[name]?.image
        case .renderbuffer(let name): renderbuffers[name]?.image
        case nil: nil
        }
    }

    func checkFramebufferStatus(_ target: GLenum) -> GLenum {
        guard target == GL.framebuffer else {
            setError(GL.invalidEnum)
            return 0
        }
        guard boundFramebuffer != 0, let framebuffer = framebuffers[boundFramebuffer] else { return GL.framebufferComplete }
        guard framebuffer.color != nil || framebuffer.depth != nil || framebuffer.stencil != nil else {
            return GL.framebufferIncompleteMissingAttachment
        }
        guard let color = image(of: framebuffer.color), !color.isDepthStencil else {
            return framebuffer.color == nil ? GL.framebufferUnsupported : GL.framebufferIncompleteAttachment
        }
        if let depthStencil = image(of: framebuffer.depth) ?? image(of: framebuffer.stencil) {
            guard depthStencil.isDepthStencil else { return GL.framebufferIncompleteAttachment }
            guard depthStencil.width == color.width, depthStencil.height == color.height else {
                return GL.framebufferIncompleteDimensions
            }
        }
        return GL.framebufferComplete
    }

    /// The bound framebuffer, ready to render into; nil when incomplete.
    func currentTarget() -> GLRenderTarget? {
        if boundFramebuffer == 0 {
            guard let color = defaultColor, let depthStencil = defaultDepthStencil,
                  let pass = try? frame.renderPass(color: color.format, depthStencil: depthStencil.format)
            else { return nil }
            if defaultVkFramebuffer == nil {
                defaultVkFramebuffer = makeVkFramebuffer(pass: pass, color: color, depthStencil: depthStencil)
            }
            guard let vk = defaultVkFramebuffer else { return nil }
            return GLRenderTarget(color: color, depthStencil: depthStencil, framebuffer: vk, renderPass: pass)
        }
        guard checkFramebufferStatus(GL.framebuffer) == GL.framebufferComplete,
              let framebuffer = framebuffers[boundFramebuffer],
              let color = image(of: framebuffer.color)
        else { return nil }
        let depthStencil = image(of: framebuffer.depth) ?? image(of: framebuffer.stencil)
        guard let pass = try? frame.renderPass(color: color.format, depthStencil: depthStencil?.format) else { return nil }
        let images = [color.serial] + (depthStencil.map { [$0.serial] } ?? [])
        if framebuffer.vkFramebuffer == nil || framebuffer.builtFor != images {
            if let old = framebuffer.vkFramebuffer {
                let device = device.device
                frame.retire { vkDestroyFramebuffer(device, old, nil) }
            }
            framebuffer.vkFramebuffer = makeVkFramebuffer(pass: pass, color: color, depthStencil: depthStencil)
            framebuffer.builtFor = images
        }
        guard let vk = framebuffer.vkFramebuffer else { return nil }
        return GLRenderTarget(color: color, depthStencil: depthStencil, framebuffer: vk, renderPass: pass)
    }

    private func makeVkFramebuffer(pass: VkRenderPass, color: GLImage, depthStencil: GLImage?) -> VkFramebuffer? {
        var views: [VkImageView?] = [color.view]
        if let depthStencil { views.append(depthStencil.view) }
        var framebuffer: VkFramebuffer?
        let result = views.withUnsafeBufferPointer { viewsPtr in
            var info = VkFramebufferCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
            info.renderPass = pass
            info.attachmentCount = UInt32(viewsPtr.count)
            info.pAttachments = viewsPtr.baseAddress
            info.width = UInt32(color.width)
            info.height = UInt32(color.height)
            info.layers = 1
            return vkCreateFramebuffer(device.device, &info, nil, &framebuffer)
        }
        return result == VK_SUCCESS ? framebuffer : nil
    }

    // MARK: - Clear

    func clear(_ mask: GLenum) {
        guard let target = currentTarget() else { return setError(GL.invalidFramebufferOperation) }
        var attachments: [VkClearAttachment] = []
        if mask & GL.colorBufferBit != 0 {
            var attachment = VkClearAttachment()
            attachment.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue)
            attachment.colorAttachment = 0
            attachment.clearValue = VkClearValue(color: VkClearColorValue(float32: (clearColor.x, clearColor.y, clearColor.z, clearColor.w)))
            attachments.append(attachment)
        }
        if target.depthStencil != nil {
            var aspect: UInt32 = 0
            if mask & GL.depthBufferBit != 0 { aspect |= VK_IMAGE_ASPECT_DEPTH_BIT.rawValue }
            if mask & GL.stencilBufferBit != 0 { aspect |= VK_IMAGE_ASPECT_STENCIL_BIT.rawValue }
            if aspect != 0 {
                var attachment = VkClearAttachment()
                attachment.aspectMask = VkImageAspectFlags(aspect)
                attachment.clearValue = VkClearValue(
                    depthStencil: VkClearDepthStencilValue(depth: 1, stencil: UInt32(truncatingIfNeeded: clearStencil))
                )
                attachments.append(attachment)
            }
        }
        guard !attachments.isEmpty, let rect = clipRect(in: target) else { return }
        frame.beginPass(target)
        var clearRect = VkClearRect(rect: rect, baseArrayLayer: 0, layerCount: 1)
        attachments.withUnsafeBufferPointer { ptr in
            vkCmdClearAttachments(frame.commandBuffer, UInt32(ptr.count), ptr.baseAddress, 1, &clearRect)
        }
    }

    /// The scissor box when the test is on, else the whole target, cut to
    /// the target. Nil when nothing is left. GL's window y and Vulkan's
    /// framebuffer y count the same rows, so no flip.
    func clipRect(in target: GLRenderTarget) -> VkRect2D? {
        var x0 = 0, y0 = 0, x1 = target.width, y1 = target.height
        if scissorTest {
            x0 = max(x0, Int(scissorBox.x))
            y0 = max(y0, Int(scissorBox.y))
            x1 = min(x1, Int(scissorBox.x) + Int(scissorBox.width))
            y1 = min(y1, Int(scissorBox.y) + Int(scissorBox.height))
        }
        guard x1 > x0, y1 > y0 else { return nil }
        return VkRect2D(
            offset: VkOffset2D(x: Int32(x0), y: Int32(y0)),
            extent: VkExtent2D(width: UInt32(x1 - x0), height: UInt32(y1 - y0))
        )
    }

    // MARK: - Read back

    func readPixels(_ x: GLint, _ y: GLint, _ width: GLsizei, _ height: GLsizei, _ format: GLenum, _ type: GLenum, _ pixels: UnsafeMutableRawPointer?) {
        guard width >= 0, height >= 0 else { return setError(GL.invalidValue) }
        guard type == GL.unsignedByte, format == GL.rgba || format == GL.rgb else { return setError(GL.invalidOperation) }
        guard let target = currentTarget() else { return setError(GL.invalidFramebufferOperation) }
        guard let pixels, width > 0, height > 0 else { return }
        let image = target.color
        let x0 = max(0, Int(x)), y0 = max(0, Int(y))
        let x1 = min(image.width, Int(x) + Int(width)), y1 = min(image.height, Int(y) + Int(height))
        guard x1 > x0, y1 > y0 else { return }
        let copyWidth = x1 - x0, copyHeight = y1 - y0

        guard let slot = try? frame.arena.allocate(copyWidth * copyHeight * 4, alignment: 4) else {
            return setError(GL.outOfMemory)
        }
        frame.endPass()
        let cmd = frame.begin()
        frame.transition(image, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
        var region = VkBufferImageCopy()
        region.bufferOffset = VkDeviceSize(slot.offset)
        region.imageSubresource = Self.colorLayers(level: 0)
        region.imageOffset = VkOffset3D(x: Int32(x0), y: Int32(y0), z: 0)
        region.imageExtent = VkExtent3D(width: UInt32(copyWidth), height: UInt32(copyHeight), depth: 1)
        vkCmdCopyImageToBuffer(cmd, image.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, slot.buffer, 1, &region)
        var barrier = VkBufferMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER
        barrier.srcAccessMask = VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
        barrier.dstAccessMask = VkAccessFlags(VK_ACCESS_HOST_READ_BIT.rawValue)
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.buffer = slot.buffer
        barrier.offset = VkDeviceSize(slot.offset)
        barrier.size = VkDeviceSize(copyWidth * copyHeight * 4)
        vkCmdPipelineBarrier(
            cmd, VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue),
            VkPipelineStageFlags(VK_PIPELINE_STAGE_HOST_BIT.rawValue), 0, 0, nil, 1, &barrier, 0, nil
        )
        // Waits; the arena is only rewound, so the copy is still there.
        frame.submit()

        let components = format == GL.rgba ? 4 : 3
        let rowBytes = (Int(width) * components + packAlignment - 1) / packAlignment * packAlignment
        let source = UnsafeRawPointer(slot.pointer).assumingMemoryBound(to: UInt8.self)
        let destination = pixels.assumingMemoryBound(to: UInt8.self)
        for row in 0..<copyHeight {
            let s = source + row * copyWidth * 4
            let d = destination + (y0 - Int(y) + row) * rowBytes + (x0 - Int(x)) * components
            if components == 4 {
                d.update(from: s, count: copyWidth * 4)
            } else {
                for i in 0..<copyWidth {
                    d[i * 3] = s[i * 4]; d[i * 3 + 1] = s[i * 4 + 1]; d[i * 3 + 2] = s[i * 4 + 2]
                }
            }
        }
    }

    // MARK: - Present

    /// End of Kivy's frame: framebuffer 0 into the shader node's image —
    /// flipped, since GL's row 0 is the bottom and the composite's is the
    /// top — then everything submitted.
    public func present() {
        frame.endPass()
        if let target = presentTarget, let color = defaultColor {
            let cmd = frame.begin()
            frame.transition(color, to: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
            presentBarrier(cmd, target.image, from: target.layout, to: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL)
            var blit = VkImageBlit()
            blit.srcSubresource = Self.colorLayers(level: 0)
            blit.dstSubresource = Self.colorLayers(level: 0)
            blit.srcOffsets.1 = VkOffset3D(x: Int32(color.width), y: Int32(color.height), z: 1)
            blit.dstOffsets.0 = VkOffset3D(x: 0, y: Int32(target.height), z: 0)
            blit.dstOffsets.1 = VkOffset3D(x: Int32(target.width), y: 0, z: 1)
            let filter = color.width == target.width && color.height == target.height ? VK_FILTER_NEAREST : VK_FILTER_LINEAR
            vkCmdBlitImage(cmd, color.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, target.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, filter)
            presentBarrier(cmd, target.image, from: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, to: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)
            presentTarget?.layout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        }
        frame.submit()
    }

    /// The node's image is the engine's to sample, so its uses on either
    /// side are the composite's fragment shader.
    private func presentBarrier(_ cmd: VkCommandBuffer, _ image: VkImage, from: VkImageLayout, to: VkImageLayout) {
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        let shaderRead = VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue)
        let transferWrite = VkAccessFlags(VK_ACCESS_TRANSFER_WRITE_BIT.rawValue)
        barrier.srcAccessMask = from == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL ? transferWrite : (from == VK_IMAGE_LAYOUT_UNDEFINED ? 0 : shaderRead)
        barrier.dstAccessMask = to == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL ? transferWrite : shaderRead
        barrier.oldLayout = from
        barrier.newLayout = to
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image
        barrier.subresourceRange = VkImageSubresourceRange(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel: 0, levelCount: 1, baseArrayLayer: 0, layerCount: 1
        )
        let fragment = VkPipelineStageFlags(VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT.rawValue)
        let transfer = VkPipelineStageFlags(VK_PIPELINE_STAGE_TRANSFER_BIT.rawValue)
        let top = VkPipelineStageFlags(VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT.rawValue)
        let source = from == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL ? transfer : (from == VK_IMAGE_LAYOUT_UNDEFINED ? top : fragment)
        let destination = to == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL ? transfer : fragment
        vkCmdPipelineBarrier(cmd, source, destination, 0, 0, nil, 0, nil, 1, &barrier)
    }
}
