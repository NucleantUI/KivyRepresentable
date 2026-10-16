//
//  KivyRenderNode.swift
//  KivyRepresentable
//
//  NucleantUI's node with Kivy's case added — what a `KivyApp`'s windows
//  render with.
//

import CVulkan
import NucleantVulkan
import NucleantThorVG
import NucleantSkia
import NucleantUI

public final class KivyRenderNode: NucleantContainerNode, @unchecked Sendable {

    public enum Context: NucleantNodeContext {
        public typealias Node = KivyRenderNode

        case thor(ThorShaderNode<KivyRenderNode>)
        case skia(SkiaShaderNode<KivyRenderNode>)
        case compute(ComputeShaderNode<KivyRenderNode>)
        case vertexShader(VertFragShaderNode<KivyRenderNode>)
        case image(ImageNode<KivyRenderNode>)
        case externalTexture(ExternalTextureNode<KivyRenderNode>)
        case renderTexture(RenderTextureNode<KivyRenderNode>)

        case kivy(KivyShaderNode<KivyRenderNode>)
    }

    public let id: Int
    public let context: Context
    public var needsRender: Bool = true
    public var compositeRect: SIMD4<Double>?
    public var compositeScissor: SIMD4<Double>?
    public var compositesToWindow: Bool = true

    public init(id: Int, context: Context) {
        self.id = id
        self.context = context
    }

    public func observeContext() {
        switch context {
        case .thor(let node): observe(node)
        case .skia(let node): observe(node)
        case .compute(let node): observe(node)
        case .vertexShader(let node): observe(node)
        case .image(let node): observe(node)
        case .externalTexture(let node): observe(node)
        case .renderTexture(let node): observe(node)
        case .kivy(let node): observe(node)
        }
    }

    public func update(engine: Engine, cmd: VkCommandBuffer) {
        // A KivyAppView laid out in this window's pass is waiting for the
        // window's engine. The node that hands it over stays due, so the
        // next frame — whose `onUpdate` starts Kivy — is drawn too.
        // The engine draws on the main thread, as the window's frame runs.
        nonisolated(unsafe) let drawing = engine
        let handedOver = MainActor.assumeIsolated { KivyAppSession.handOver(drawing) }
        defer { if handedOver { needsRender = true } }
        guard needsRender else { return }
        switch context {
        case .thor(let node): node.update(engine, slot: self, cmd: cmd)
        case .skia(let node): node.update(engine, slot: self, cmd: cmd)
        case .compute(let node): node.update(engine, slot: self, cmd: cmd)
        case .vertexShader(let node): node.update(engine, slot: self, cmd: cmd)
        case .image(let node): node.update(engine, slot: self, cmd: cmd)
        case .externalTexture(let node): node.update(engine, slot: self, cmd: cmd)
        case .renderTexture(let node): node.update(engine, slot: self, cmd: cmd)
        case .kivy(let node): node.update(engine, slot: self, cmd: cmd)
        }
        // Kivy runs on its own clock, ticked from the engine's frame
        // (`onUpdate`), so its slot never idles: clearing it would stop the
        // frames that tick Kivy.
        if case .kivy = context { return }
        needsRender = false
    }

    public func destroyResources(engine: Engine) {
        switch context {
        case .thor(let node): node.destroyResources(engine)
        case .skia(let node): node.destroyResources(engine)
        case .compute(let node): node.destroyResources(engine)
        case .vertexShader(let node): node.destroyResources(engine)
        case .image(let node): node.destroyResources(engine)
        case .externalTexture(let node): node.destroyResources(engine)
        case .renderTexture(let node): node.destroyResources(engine)
        case .kivy(let node): node.destroyResources(engine)
        }
    }

    public func getImageView() -> VkImageView? {
        guard compositesToWindow else { return nil }
        switch context {
        case .thor(let node): return node.imageView
        case .skia(let node): return node.imageView
        case .compute(let node): return node.imageView
        case .vertexShader(let node): return node.imageView
        case .image(let node): return node.imageView
        case .externalTexture(let node): return node.imageView
        case .renderTexture(let node): return node.imageView
        case .kivy(let node): return node.imageView
        }
    }

    public func resizeToFitWindow(width: Int, height: Int, engine: Engine) {
        switch context {
        case .thor(let node) where compositesToWindow && compositeRect == nil:
            engine.resizeThorNode(node, id: id, width: width, height: height)
        case .skia(let node) where compositesToWindow && compositeRect == nil:
            engine.resizeSkiaNode(node, id: id, width: width, height: height)
        case .thor, .skia, .compute, .vertexShader, .image, .externalTexture, .renderTexture:
            break
        case .kivy:
            break
        }
    }
}
