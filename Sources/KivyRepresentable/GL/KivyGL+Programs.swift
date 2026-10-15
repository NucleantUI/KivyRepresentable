//
//  KivyGL+Programs.swift
//  KivyRepresentable
//
//  Shaders and programs. glCompileShader checks a stage on its own;
//  glLinkProgram translates both stages against one set of locations
//  (GLSLTranslator.swift), compiles them to SPIR-V with NucleantShader's
//  shaderc, and lays out the uniform block glUniform* writes into.
//

import Foundation
@preconcurrency import CVulkan
import NucleantShader

extension KivyGL {

    // MARK: - Shaders

    func createShader(_ type: GLenum) -> GLuint {
        let stage: GLSLStage
        switch type {
        case GL.vertexShader: stage = .vertex
        case GL.fragmentShader: stage = .fragment
        default:
            setError(GL.invalidEnum)
            return 0
        }
        let name = nextName
        nextName += 1
        shaders[name] = GLShader(stage: stage)
        return name
    }

    func shaderSource(_ name: GLuint, _ count: GLsizei, _ strings: UnsafePointer<UnsafePointer<CChar>?>?, _ lengths: UnsafePointer<GLint>?) {
        guard let shader = shaders[name] else { return setError(GL.invalidValue) }
        guard count >= 0 else { return setError(GL.invalidValue) }
        var source = ""
        for index in 0..<Int(count) {
            guard let string = strings?[index] else { continue }
            if let lengths, lengths[index] >= 0 {
                let bytes = UnsafeRawBufferPointer(start: string, count: Int(lengths[index]))
                source += String(decoding: bytes, as: UTF8.self)
            } else {
                source += String(cString: string)
            }
        }
        shader.source = source
    }

    func compileShader(_ name: GLuint) {
        guard let shader = shaders[name] else { return setError(GL.invalidValue) }
        shader.compiled = false
        shader.parsed = nil
        do {
            let parsed = try GLSLShaderSource(shader.source)
            let glsl = GLSLTranslator.translate(parsed, stage: shader.stage, interface: GLSLInterface(single: parsed))
            if compileSPIRV(glsl, stage: shader.stage) != nil {
                shader.parsed = parsed
                shader.compiled = true
                shader.infoLog = ""
            } else {
                shader.infoLog = VKShaderCompiler.shared.lastErrorMessage ?? "compilation failed"
            }
        } catch {
            shader.infoLog = "ERROR: \(error)"
        }
    }

    func compileSPIRV(_ glsl: String, stage: GLSLStage) -> [UInt32]? {
        VKShaderCompiler.shared.compile(
            source: glsl,
            stage: stage == .vertex ? .vertex : .fragment,
            filename: stage == .vertex ? "kivy.vert" : "kivy.frag"
        )
    }

    func deleteShader(_ name: GLuint) {
        guard name != 0 else { return }
        guard let shader = shaders[name] else { return setError(GL.invalidValue) }
        if programs.values.contains(where: { $0.shaders.contains(name) }) {
            shader.deletePending = true
        } else {
            shaders[name] = nil
        }
    }

    func getShader(_ name: GLuint, _ pname: GLenum) -> GLint? {
        guard let shader = shaders[name] else {
            setError(GL.invalidValue)
            return nil
        }
        switch pname {
        case GL.shaderType: return GLint(shader.stage == .vertex ? GL.vertexShader : GL.fragmentShader)
        case GL.compileStatus: return shader.compiled ? 1 : 0
        case GL.deleteStatus: return shader.deletePending ? 1 : 0
        case GL.infoLogLength: return shader.infoLog.isEmpty ? 0 : GLint(shader.infoLog.utf8.count + 1)
        case GL.shaderSourceLength: return shader.source.isEmpty ? 0 : GLint(shader.source.utf8.count + 1)
        default:
            setError(GL.invalidEnum)
            return nil
        }
    }

    func shaderInfoLog(_ name: GLuint) -> String? {
        guard let shader = shaders[name] else {
            setError(GL.invalidValue)
            return nil
        }
        return shader.infoLog
    }

    func shaderSourceText(_ name: GLuint) -> String? {
        guard let shader = shaders[name] else {
            setError(GL.invalidValue)
            return nil
        }
        return shader.source
    }

    // MARK: - Programs

    func createProgram() -> GLuint {
        let name = nextName
        nextName += 1
        programs[name] = GLProgram()
        return name
    }

    func attachShader(_ programName: GLuint, _ shaderName: GLuint) {
        guard let program = programs[programName], shaders[shaderName] != nil else { return setError(GL.invalidValue) }
        guard !program.shaders.contains(shaderName) else { return setError(GL.invalidOperation) }
        program.shaders.append(shaderName)
    }

    func detachShader(_ programName: GLuint, _ shaderName: GLuint) {
        guard let program = programs[programName] else { return setError(GL.invalidValue) }
        guard let index = program.shaders.firstIndex(of: shaderName) else { return setError(GL.invalidOperation) }
        program.shaders.remove(at: index)
        if let shader = shaders[shaderName], shader.deletePending,
           !programs.values.contains(where: { $0.shaders.contains(shaderName) }) {
            shaders[shaderName] = nil
        }
    }

    func bindAttribLocation(_ programName: GLuint, _ index: GLuint, _ name: String) {
        guard let program = programs[programName] else { return setError(GL.invalidValue) }
        guard Int(index) < Self.maxVertexAttributes else { return setError(GL.invalidValue) }
        program.boundAttributes[name] = Int(index)
    }

    func linkProgram(_ name: GLuint) {
        guard let program = programs[name] else { return setError(GL.invalidValue) }
        program.linked = false
        let attached = program.shaders.compactMap { shaders[$0] }
        guard let vertex = attached.first(where: { $0.stage == .vertex })?.parsed,
              let fragment = attached.first(where: { $0.stage == .fragment })?.parsed
        else {
            program.infoLog = "a compiled vertex and fragment shader must be attached"
            return
        }

        // Attribute locations: glBindAttribLocation's first, then the lowest
        // free ones, in declaration order.
        var locations: [String: Int] = [:]
        var used = Set<Int>()
        for attribute in vertex.attributes {
            if let bound = program.boundAttributes[attribute.name] {
                locations[attribute.name] = bound
                used.formUnion(bound..<bound + attribute.type.locations * attribute.count)
            }
        }
        for attribute in vertex.attributes where locations[attribute.name] == nil {
            let size = attribute.type.locations * attribute.count
            var start = 0
            while (start..<start + size).contains(where: used.contains) { start += 1 }
            locations[attribute.name] = start
            used.formUnion(start..<start + size)
        }
        guard (used.max() ?? 0) < Self.maxVertexAttributes else {
            program.infoLog = "too many vertex attributes"
            return
        }

        let interface = GLSLInterface(stages: [vertex, fragment], attributes: locations)
        guard let vertexSPIRV = compileSPIRV(GLSLTranslator.translate(vertex, stage: .vertex, interface: interface), stage: .vertex) else {
            program.infoLog = VKShaderCompiler.shared.lastErrorMessage ?? "vertex shader failed to link"
            return
        }
        guard let fragmentSPIRV = compileSPIRV(GLSLTranslator.translate(fragment, stage: .fragment, interface: interface), stage: .fragment) else {
            program.infoLog = VKShaderCompiler.shared.lastErrorMessage ?? "fragment shader failed to link"
            return
        }

        destroyPipelineObjects(of: program)
        do {
            program.vertexModule = try makeModule(vertexSPIRV)
            program.fragmentModule = try makeModule(fragmentSPIRV)
        } catch {
            program.infoLog = "could not create shader modules"
            return
        }

        // Uniforms: the block's in its order, then the samplers.
        let layout = GLSLBlockLayout(interface.blockUniforms)
        var uniforms: [GLProgram.Uniform] = []
        var locationTable: [(uniform: Int, element: Int)] = []
        for member in layout.members {
            uniforms.append(.init(variable: member.variable, location: locationTable.count, offset: member.offset, stride: member.stride, binding: nil))
            for element in 0..<member.variable.count { locationTable.append((uniforms.count - 1, element)) }
        }
        let samplerVariables = [vertex, fragment].flatMap(\.uniforms).filter(\.type.isSampler)
        var seen = Set<String>()
        program.samplerUnits = [:]
        for variable in samplerVariables where seen.insert(variable.name).inserted {
            let binding = interface.samplerBindings[variable.name]!
            uniforms.append(.init(variable: variable, location: locationTable.count, offset: nil, stride: 0, binding: binding))
            for element in 0..<variable.count { locationTable.append((uniforms.count - 1, element)) }
            program.samplerUnits[binding] = [Int](repeating: 0, count: variable.count)
        }
        program.uniforms = uniforms
        program.locations = locationTable
        program.blockSize = interface.blockUniforms.isEmpty ? 0 : layout.size
        program.blockData = [UInt8](repeating: 0, count: program.blockSize)
        program.attributes = vertex.attributes.map { .init(variable: $0, location: locations[$0.name]!) }

        do {
            try makeLayouts(for: program)
        } catch {
            program.infoLog = "could not create the pipeline layout"
            return
        }
        program.generation += 1
        program.linked = true
        program.infoLog = ""
    }

    private func makeModule(_ spirv: [UInt32]) throws -> VkShaderModule {
        var module: VkShaderModule?
        let result = spirv.withUnsafeBufferPointer { words in
            var info = VkShaderModuleCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
            info.codeSize = words.count * 4
            info.pCode = words.baseAddress
            return vkCreateShaderModule(device.device, &info, nil, &module)
        }
        guard result == VK_SUCCESS, let module else { throw KivyGLError.image }
        return module
    }

    /// Binding 0 the uniform block (when there is one), then one combined
    /// image sampler binding per sampler uniform.
    private func makeLayouts(for program: GLProgram) throws {
        let stages = VkShaderStageFlags(VK_SHADER_STAGE_VERTEX_BIT.rawValue | VK_SHADER_STAGE_FRAGMENT_BIT.rawValue)
        var bindings: [VkDescriptorSetLayoutBinding] = []
        if program.blockSize > 0 {
            bindings.append(VkDescriptorSetLayoutBinding(
                binding: 0, descriptorType: VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, descriptorCount: 1,
                stageFlags: stages, pImmutableSamplers: nil
            ))
        }
        for uniform in program.uniforms {
            guard let binding = uniform.binding else { continue }
            bindings.append(VkDescriptorSetLayoutBinding(
                binding: UInt32(binding), descriptorType: VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                descriptorCount: UInt32(uniform.variable.count), stageFlags: stages, pImmutableSamplers: nil
            ))
        }
        var setLayout: VkDescriptorSetLayout?
        let setResult = bindings.withUnsafeBufferPointer { ptr in
            var info = VkDescriptorSetLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
            info.bindingCount = UInt32(ptr.count)
            info.pBindings = ptr.baseAddress
            return vkCreateDescriptorSetLayout(device.device, &info, nil, &setLayout)
        }
        guard setResult == VK_SUCCESS, let setLayout else { throw KivyGLError.image }
        program.setLayout = setLayout

        var layoutOpt: VkDescriptorSetLayout? = setLayout
        var pipelineLayout: VkPipelineLayout?
        let result = withUnsafePointer(to: &layoutOpt) { layoutPtr in
            var info = VkPipelineLayoutCreateInfo()
            info.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
            info.setLayoutCount = 1
            info.pSetLayouts = layoutPtr
            return vkCreatePipelineLayout(device.device, &info, nil, &pipelineLayout)
        }
        guard result == VK_SUCCESS, let pipelineLayout else { throw KivyGLError.image }
        program.pipelineLayout = pipelineLayout
    }

    /// The program's modules, layouts and pipelines, once no recorded work
    /// can still use them.
    func destroyPipelineObjects(of program: GLProgram) {
        let device = device.device
        let stale = pipelines.filter { $0.key.program == program.serial }
        for key in stale.keys { pipelines[key] = nil }
        let (vertex, fragment, setLayout, pipelineLayout) = (program.vertexModule, program.fragmentModule, program.setLayout, program.pipelineLayout)
        program.vertexModule = nil
        program.fragmentModule = nil
        program.setLayout = nil
        program.pipelineLayout = nil
        let release = {
            for pipeline in stale.values { vkDestroyPipeline(device, pipeline, nil) }
            if let vertex { vkDestroyShaderModule(device, vertex, nil) }
            if let fragment { vkDestroyShaderModule(device, fragment, nil) }
            if let setLayout { vkDestroyDescriptorSetLayout(device, setLayout, nil) }
            if let pipelineLayout { vkDestroyPipelineLayout(device, pipelineLayout, nil) }
        }
        if let frame { frame.retire(release) } else { release() }
    }

    func useProgram(_ name: GLuint) {
        if name != 0 {
            guard let program = programs[name] else { return setError(GL.invalidValue) }
            guard program.linked else { return setError(GL.invalidOperation) }
        }
        if let previous = programs[currentProgram], previous.deletePending, currentProgram != name {
            removeProgram(currentProgram)
        }
        currentProgram = name
    }

    func deleteProgram(_ name: GLuint) {
        guard name != 0 else { return }
        guard let program = programs[name] else { return setError(GL.invalidValue) }
        if currentProgram == name {
            program.deletePending = true
        } else {
            removeProgram(name)
        }
    }

    private func removeProgram(_ name: GLuint) {
        guard let program = programs.removeValue(forKey: name) else { return }
        destroyPipelineObjects(of: program)
        for shaderName in program.shaders {
            if let shader = shaders[shaderName], shader.deletePending,
               !programs.values.contains(where: { $0.shaders.contains(shaderName) }) {
                shaders[shaderName] = nil
            }
        }
    }

    func getProgram(_ name: GLuint, _ pname: GLenum) -> GLint? {
        guard let program = programs[name] else {
            setError(GL.invalidValue)
            return nil
        }
        switch pname {
        case GL.linkStatus: return program.linked ? 1 : 0
        case GL.validateStatus: return program.linked ? 1 : 0
        case GL.deleteStatus: return program.deletePending ? 1 : 0
        case GL.infoLogLength: return program.infoLog.isEmpty ? 0 : GLint(program.infoLog.utf8.count + 1)
        case GL.attachedShaders: return GLint(program.shaders.count)
        case GL.activeAttributes: return GLint(program.attributes.count)
        case GL.activeAttributeMaxLength: return GLint((program.attributes.map(\.variable.name.utf8.count).max() ?? -1) + 1)
        case GL.activeUniforms: return GLint(program.uniforms.count)
        case GL.activeUniformMaxLength: return GLint((program.uniforms.map { activeName($0.variable).utf8.count }.max() ?? -1) + 1)
        default:
            setError(GL.invalidEnum)
            return nil
        }
    }

    func programInfoLog(_ name: GLuint) -> String? {
        guard let program = programs[name] else {
            setError(GL.invalidValue)
            return nil
        }
        return program.infoLog
    }

    /// GL's name for an active uniform: an array's is `name[0]`.
    func activeName(_ variable: GLSLVariable) -> String {
        variable.arraySize == nil ? variable.name : variable.name + "[0]"
    }

    func getAttribLocation(_ programName: GLuint, _ name: String) -> GLint {
        guard let program = programs[programName] else {
            setError(GL.invalidValue)
            return -1
        }
        guard program.linked else {
            setError(GL.invalidOperation)
            return -1
        }
        return GLint(program.attributes.first { $0.variable.name == name }?.location ?? -1)
    }

    func getUniformLocation(_ programName: GLuint, _ name: String) -> GLint {
        guard let program = programs[programName] else {
            setError(GL.invalidValue)
            return -1
        }
        guard program.linked else {
            setError(GL.invalidOperation)
            return -1
        }
        var base = name
        var element = 0
        if name.hasSuffix("]"), let open = name.lastIndex(of: "[") {
            base = String(name[..<open])
            guard let index = Int(name[name.index(after: open)..<name.index(before: name.endIndex)]) else { return -1 }
            element = index
        }
        guard let uniform = program.uniforms.first(where: { $0.variable.name == base }) else { return -1 }
        if base != name && uniform.variable.arraySize == nil && element != 0 { return -1 }
        guard element < uniform.variable.count else { return -1 }
        return GLint(uniform.location + element)
    }

    // MARK: - Uniform values

    /// `count` values of `components` scalars each from location on, the
    /// way glUniform{1,2,3,4}{f,i}[v] writes them.
    func setUniform(_ location: GLint, count: GLsizei, components: Int, float: ((Int) -> Float)?, int: ((Int) -> Int32)?) {
        guard location != -1 else { return }
        guard let program = programs[currentProgram], program.linked else { return setError(GL.invalidOperation) }
        guard location >= 0, Int(location) < program.locations.count, count >= 0 else { return setError(GL.invalidOperation) }
        let (uniformIndex, element) = program.locations[Int(location)]
        let uniform = program.uniforms[uniformIndex]
        let type = uniform.variable.type
        guard type.columns == 1, type.components == components else { return setError(GL.invalidOperation) }
        guard count == 1 || uniform.variable.arraySize != nil else { return setError(GL.invalidOperation) }
        let elements = min(Int(count), uniform.variable.count - element)

        if let binding = uniform.binding {
            guard let int else { return setError(GL.invalidOperation) }
            for index in 0..<elements {
                program.samplerUnits[binding]?[element + index] = Int(int(index))
            }
            return
        }
        guard let offset = uniform.offset else { return }
        program.blockData.withUnsafeMutableBytes { bytes in
            for index in 0..<elements {
                let base = offset + (element + index) * uniform.stride
                for component in 0..<components {
                    let value = index * components + component
                    let at = base + component * 4
                    if type.isBool {
                        let on = float.map { $0(value) != 0 } ?? (int!(value) != 0)
                        bytes.storeBytes(of: UInt32(on ? 1 : 0), toByteOffset: at, as: UInt32.self)
                    } else if type.isInteger {
                        bytes.storeBytes(of: int.map { $0(value) } ?? Int32(float!(value)), toByteOffset: at, as: Int32.self)
                    } else {
                        bytes.storeBytes(of: float.map { $0(value) } ?? Float(int!(value)), toByteOffset: at, as: Float.self)
                    }
                }
            }
        }
    }

    func setUniformMatrix(_ location: GLint, count: GLsizei, size: Int, transpose: Bool, values: UnsafePointer<GLfloat>?) {
        guard location != -1 else { return }
        guard let program = programs[currentProgram], program.linked else { return setError(GL.invalidOperation) }
        guard location >= 0, Int(location) < program.locations.count, count >= 0, let values else { return setError(GL.invalidOperation) }
        guard !transpose else { return setError(GL.invalidValue) }
        let (uniformIndex, element) = program.locations[Int(location)]
        let uniform = program.uniforms[uniformIndex]
        guard uniform.variable.type.columns == size, let offset = uniform.offset else { return setError(GL.invalidOperation) }
        let elements = min(Int(count), uniform.variable.count - element)
        program.blockData.withUnsafeMutableBytes { bytes in
            for index in 0..<elements {
                let base = offset + (element + index) * uniform.stride
                for column in 0..<size {
                    for row in 0..<size {
                        let value = values[index * size * size + column * size + row]
                        bytes.storeBytes(of: value, toByteOffset: base + column * 16 + row * 4, as: Float.self)
                    }
                }
            }
        }
    }

    /// glGetUniform{f,i}v: the value at `location`, as floats.
    func getUniform(_ programName: GLuint, _ location: GLint) -> [Float]? {
        guard let program = programs[programName], program.linked,
              location >= 0, Int(location) < program.locations.count
        else {
            setError(GL.invalidOperation)
            return nil
        }
        let (uniformIndex, element) = program.locations[Int(location)]
        let uniform = program.uniforms[uniformIndex]
        if let binding = uniform.binding {
            return [Float(program.samplerUnits[binding]?[element] ?? 0)]
        }
        guard let offset = uniform.offset else { return nil }
        let type = uniform.variable.type
        let base = offset + element * uniform.stride
        return program.blockData.withUnsafeBytes { bytes in
            var out: [Float] = []
            for column in 0..<type.columns {
                for row in 0..<type.components {
                    let at = base + column * 16 + row * 4
                    if type.isBool {
                        out.append(Float(bytes.load(fromByteOffset: at, as: UInt32.self)))
                    } else if type.isInteger {
                        out.append(Float(bytes.load(fromByteOffset: at, as: Int32.self)))
                    } else {
                        out.append(bytes.load(fromByteOffset: at, as: Float.self))
                    }
                }
            }
            return out
        }
    }
}
