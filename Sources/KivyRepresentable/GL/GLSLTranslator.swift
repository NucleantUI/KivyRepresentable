//
//  GLSLTranslator.swift
//  KivyRepresentable
//
//  Kivy's shaders are GLSL ES 1.00 — `attribute`, `varying`, loose
//  uniforms, `gl_FragColor`, `texture2D`, no `#version`. Vulkan takes
//  SPIR-V from GLSL 450, where every input and output has a location and
//  every uniform lives in a block or is a bound sampler. This rewrites the
//  declarations and leaves the code that uses them alone:
//
//    attribute T a;   →  layout(location = n) in T a;
//    varying T v;     →  layout(location = n) out/in T v;   (by name, so
//                        both stages agree)
//    uniform sampler2D s;  →  layout(set = 0, binding = n) uniform sampler2D s;
//    uniform T u;     →  a member of one std140 block at binding 0, holding
//                        every plain uniform of the program in the same order
//                        in both stages, so its offsets are the same in both.
//
//  The vertex stage's `main` is wrapped so GL's clip-space depth (-w...w)
//  lands in Vulkan's (0...w). Nothing is flipped in y: GL's window row 0 and
//  Vulkan's framebuffer row 0 are both the first row in memory, so a
//  GL-convention scene rendered unchanged comes out in GL's memory order —
//  what Kivy's Fbo textures and glReadPixels expect.
//

import Foundation

/// The GLSL types a uniform, attribute or varying can have.
enum GLSLType: String, CaseIterable {
    case float, vec2, vec3, vec4
    case int, ivec2, ivec3, ivec4
    case bool, bvec2, bvec3, bvec4
    case mat2, mat3, mat4
    case sampler2D, samplerCube

    var isSampler: Bool { self == .sampler2D || self == .samplerCube }

    /// Scalars, or rows for a matrix.
    var components: Int {
        switch self {
        case .float, .int, .bool: 1
        case .vec2, .ivec2, .bvec2, .mat2: 2
        case .vec3, .ivec3, .bvec3, .mat3: 3
        case .vec4, .ivec4, .bvec4, .mat4: 4
        case .sampler2D, .samplerCube: 1
        }
    }

    /// Columns of a matrix; 1 for everything else.
    var columns: Int {
        switch self {
        case .mat2: 2
        case .mat3: 3
        case .mat4: 4
        default: 1
        }
    }

    var isInteger: Bool {
        switch self {
        case .int, .ivec2, .ivec3, .ivec4, .sampler2D, .samplerCube: true
        default: false
        }
    }

    var isBool: Bool {
        switch self {
        case .bool, .bvec2, .bvec3, .bvec4: true
        default: false
        }
    }

    /// The GL enum glGetActiveUniform / glGetActiveAttrib report.
    var glType: GLenum {
        switch self {
        case .float: GL.float
        case .vec2: GL.floatVec2
        case .vec3: GL.floatVec3
        case .vec4: GL.floatVec4
        case .int: GL.int
        case .ivec2: GL.intVec2
        case .ivec3: GL.intVec3
        case .ivec4: GL.intVec4
        case .bool: GL.bool
        case .bvec2: GL.boolVec2
        case .bvec3: GL.boolVec3
        case .bvec4: GL.boolVec4
        case .mat2: GL.floatMat2
        case .mat3: GL.floatMat3
        case .mat4: GL.floatMat4
        case .sampler2D: GL.sampler2D
        case .samplerCube: GL.samplerCube
        }
    }

    /// Interface locations one of these takes.
    var locations: Int { columns }

    /// std140 base alignment and size of one (non-array) value.
    var std140: (alignment: Int, size: Int) {
        if columns > 1 { return (16, 16 * columns) }
        switch components {
        case 1: return (4, 4)
        case 2: return (8, 8)
        case 3: return (16, 12)
        default: return (16, 16)
        }
    }
}

/// One declared name: `vec4 color`, `vec2 offsets[9]`.
struct GLSLVariable: Equatable {
    let name: String
    let type: GLSLType
    /// nil when not an array.
    let arraySize: Int?

    var count: Int { arraySize ?? 1 }

    var declaration: String {
        arraySize.map { "\(type.rawValue) \(name)[\($0)]" } ?? "\(type.rawValue) \(name)"
    }
}

enum GLSLStage {
    case vertex, fragment
}

/// What one shader declares, and where, in its comment-free source.
struct GLSLShaderSource {
    enum Storage { case attribute, varying, uniform }

    struct Declaration {
        let storage: Storage
        let variables: [GLSLVariable]
        /// The whole statement, `;` included, in `text`.
        let range: Range<String.Index>
    }

    /// The source with comments blanked and any `#version` line removed, as
    /// well as `#extension` lines for what Vulkan GLSL has built in.
    let text: String
    let declarations: [Declaration]

    var attributes: [GLSLVariable] { variables(.attribute) }
    var varyings: [GLSLVariable] { variables(.varying) }
    var uniforms: [GLSLVariable] { variables(.uniform) }

    private func variables(_ storage: Storage) -> [GLSLVariable] {
        declarations.filter { $0.storage == storage }.flatMap(\.variables)
    }

    enum ParseError: Error, CustomStringConvertible {
        case unsupportedType(String)
        var description: String {
            switch self {
            case .unsupportedType(let type): "unsupported type '\(type)' for attribute, varying or uniform"
            }
        }
    }

    init(_ source: String) throws {
        let text = Self.removingDirectives(Self.blankingComments(source))
        var declarations: [Declaration] = []
        var depth = 0
        var statementStart = text.startIndex
        var index = text.startIndex
        var atLineStart = true
        while index < text.endIndex {
            let char = text[index]
            if atLineStart && char == "#" {
                // A preprocessor line is never part of a statement.
                let end = text[index...].firstIndex(of: "\n") ?? text.endIndex
                index = end
                if depth == 0 { statementStart = index }
                continue
            }
            if char == "\n" {
                atLineStart = true
            } else if !char.isWhitespace {
                atLineStart = false
            }
            switch char {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { statementStart = text.index(after: index) }
            case ";" where depth == 0:
                let end = text.index(after: index)
                if let declaration = try Self.declaration(in: text, range: statementStart..<end) {
                    declarations.append(declaration)
                }
                statementStart = end
            default:
                break
            }
            index = text.index(after: index)
        }
        self.text = text
        self.declarations = declarations
    }

    private static let precisions: Set<String> = ["lowp", "mediump", "highp"]

    /// `range` as an attribute, varying or uniform declaration, if it is one.
    private static func declaration(in text: String, range: Range<String.Index>) throws -> Declaration? {
        let statement = text[range].dropLast() // the `;`
        // Leading whitespace may hold newlines from preprocessor lines.
        let words = statement.split(whereSeparator: { $0.isWhitespace })
        var position = 0
        if position < words.count, words[position] == "invariant" { position += 1 }
        guard position < words.count else { return nil }
        let storage: Storage
        switch words[position] {
        case "attribute": storage = .attribute
        case "varying": storage = .varying
        case "uniform": storage = .uniform
        default: return nil
        }
        position += 1
        if position < words.count, precisions.contains(String(words[position])) { position += 1 }
        guard position < words.count else { return nil }
        let typeName = String(words[position])
        guard let type = GLSLType(rawValue: typeName) else { throw ParseError.unsupportedType(typeName) }
        position += 1

        let declarators = words[position...].joined().split(separator: ",")
        let variables = declarators.map { declarator -> GLSLVariable in
            if let open = declarator.firstIndex(of: "["), let close = declarator.firstIndex(of: "]") {
                let name = String(declarator[..<open])
                let size = Int(declarator[declarator.index(after: open)..<close]) ?? 1
                return GLSLVariable(name: name, type: type, arraySize: size)
            }
            return GLSLVariable(name: String(declarator), type: type, arraySize: nil)
        }
        // Start the range at the first word, not at the whitespace before it.
        let start = text[range].firstIndex(where: { !$0.isWhitespace }) ?? range.lowerBound
        return Declaration(storage: storage, variables: variables, range: start..<range.upperBound)
    }

    /// Comments as spaces (newlines kept), so nothing in one is mistaken for
    /// a declaration and line numbers in errors still match.
    private static func blankingComments(_ source: String) -> String {
        var out = ""
        out.reserveCapacity(source.utf8.count)
        var chars = Array(source)
        var i = 0
        chars.append("\0")
        while i < chars.count - 1 {
            if chars[i] == "/" && chars[i + 1] == "/" {
                while i < chars.count - 1 && chars[i] != "\n" {
                    out.append(" ")
                    i += 1
                }
            } else if chars[i] == "/" && chars[i + 1] == "*" {
                out.append("  ")
                i += 2
                while i < chars.count - 1 && !(chars[i] == "*" && chars[i + 1] == "/") {
                    out.append(chars[i] == "\n" ? "\n" : " ")
                    i += 1
                }
                if i < chars.count - 1 {
                    out.append("  ")
                    i += 2
                }
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    /// GLSL ES 1.00 extensions that are core in GLSL 450.
    static let builtInExtensions = ["GL_OES_standard_derivatives"]

    private static func removingDirectives(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let directive = line.trimmingCharacters(in: .whitespaces)
            if directive.hasPrefix("#version") { return "" }
            if directive.hasPrefix("#extension"), builtInExtensions.contains(where: { directive.contains($0) }) {
                return ""
            }
            return String(line)
        }.joined(separator: "\n")
    }
}

/// What both stages of a program have to agree on.
struct GLSLInterface {
    /// Attribute name → first location.
    var attributeLocations: [String: Int] = [:]
    /// Varying name → first location.
    var varyingLocations: [String: Int] = [:]
    /// The plain uniforms, in block order; empty for no block.
    var blockUniforms: [GLSLVariable] = []
    /// Sampler name → binding (1...).
    var samplerBindings: [String: Int] = [:]

    /// For one stage on its own (glCompileShader): its own declarations.
    init(single shader: GLSLShaderSource) {
        var attributes: [String: Int] = [:]
        var next = 0
        for attribute in shader.attributes {
            attributes[attribute.name] = next
            next += attribute.type.locations * attribute.count
        }
        self.init(stages: [shader], attributes: attributes)
    }

    /// For a program: `attributes` already placed, varyings and uniforms in
    /// declaration order, vertex stage first.
    init(stages: [GLSLShaderSource], attributes: [String: Int]) {
        attributeLocations = attributes
        var nextVarying = 0
        var nextSampler = 1
        for stage in stages {
            for varying in stage.varyings where varyingLocations[varying.name] == nil {
                varyingLocations[varying.name] = nextVarying
                nextVarying += varying.type.locations * varying.count
            }
            for uniform in stage.uniforms {
                if uniform.type.isSampler {
                    if samplerBindings[uniform.name] == nil {
                        samplerBindings[uniform.name] = nextSampler
                        nextSampler += 1
                    }
                } else if !blockUniforms.contains(where: { $0.name == uniform.name }) {
                    blockUniforms.append(uniform)
                }
            }
        }
    }
}

enum GLSLTranslator {

    /// Vulkan GLSL 450 for `shader`, with the locations and bindings
    /// `interface` gives.
    static func translate(_ shader: GLSLShaderSource, stage: GLSLStage, interface: GLSLInterface) -> String {
        var body = shader.text
        // Replace back to front, so earlier ranges stay valid.
        let firstUniform = shader.declarations.first(where: {
            $0.storage == .uniform && $0.variables.contains { !$0.type.isSampler }
        })?.range.lowerBound
        for declaration in shader.declarations.reversed() {
            var lines: [String] = []
            for variable in declaration.variables {
                switch declaration.storage {
                case .attribute:
                    let location = interface.attributeLocations[variable.name] ?? 0
                    lines.append("layout(location = \(location)) in \(variable.declaration);")
                case .varying:
                    let location = interface.varyingLocations[variable.name] ?? 0
                    let direction = stage == .vertex ? "out" : "in"
                    lines.append("layout(location = \(location)) \(direction) \(variable.declaration);")
                case .uniform where variable.type.isSampler:
                    let binding = interface.samplerBindings[variable.name] ?? 1
                    lines.append("layout(set = 0, binding = \(binding)) uniform \(variable.declaration);")
                case .uniform:
                    break // in the block
                }
            }
            if declaration.range.lowerBound == firstUniform && !interface.blockUniforms.isEmpty {
                lines.insert(uniformBlock(interface.blockUniforms), at: 0)
            }
            body.replaceSubrange(declaration.range, with: lines.joined(separator: " "))
        }

        var out = "#version 450\n"
        out += "#define texture2D texture\n"
        out += "#define texture2DProj textureProj\n"
        out += "#define textureCube texture\n"
        switch stage {
        case .vertex:
            out += "#define main nui_main\n"
            out += "#line 1\n"
            out += body
            out += "\n#undef main\n"
            out += "void main() {\n"
            out += "    gl_PointSize = 1.0;\n"
            out += "    nui_main();\n"
            out += "    gl_Position.z = (gl_Position.z + gl_Position.w) * 0.5;\n"
            out += "}\n"
        case .fragment:
            if body.contains("gl_FragData") {
                out += "layout(location = 0) out vec4 nui_FragData[1];\n"
                out += "#define gl_FragData nui_FragData\n"
            } else {
                out += "layout(location = 0) out vec4 nui_FragColor;\n"
                out += "#define gl_FragColor nui_FragColor\n"
            }
            out += "#line 1\n"
            out += body
        }
        return out
    }

    static func uniformBlock(_ uniforms: [GLSLVariable]) -> String {
        let members = uniforms.map { "\($0.declaration);" }.joined(separator: " ")
        return "layout(std140, set = 0, binding = 0) uniform NUIUniforms { \(members) };"
    }
}

/// Where each plain uniform sits in the std140 block.
struct GLSLBlockLayout {
    struct Member {
        let variable: GLSLVariable
        let offset: Int
        /// Between array elements; the value's size for a non-array.
        let stride: Int
    }

    let members: [Member]
    let size: Int

    init(_ uniforms: [GLSLVariable]) {
        var offset = 0
        var members: [Member] = []
        for uniform in uniforms {
            var (alignment, size) = uniform.type.std140
            var stride = size
            if uniform.arraySize != nil {
                alignment = max(alignment, 16)
                stride = (size + 15) / 16 * 16
                size = stride * uniform.count
            }
            offset = (offset + alignment - 1) / alignment * alignment
            members.append(Member(variable: uniform, offset: offset, stride: stride))
            offset += size
        }
        self.members = members
        self.size = max(16, (offset + 15) / 16 * 16)
    }
}
