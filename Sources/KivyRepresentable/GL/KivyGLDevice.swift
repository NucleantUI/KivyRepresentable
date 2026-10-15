//
//  KivyGLDevice.swift
//  KivyRepresentable
//
//  The Vulkan device Kivy's GL table renders on: the host engine's, so the
//  image Kivy draws is one the engine can composite, or a headless one of
//  its own for running Kivy without a window (tests).
//

import Foundation
@preconcurrency import CVulkan
import NucleantVulkan

public enum KivyGLError: Error {
    case instance(Int32)
    case noPhysicalDevice
    case noQueue
    case device(Int32)
    case commandPool
    case noDepthStencilFormat
    case image
    case memory
    case buffer
}

public final class KivyGLDevice: @unchecked Sendable {
    public let physicalDevice: VkPhysicalDevice
    public let device: VkDevice
    public let queue: VkQueue
    public let queueFamilyIndex: UInt32

    let commandPool: VkCommandPool
    let memoryProperties: VkPhysicalDeviceMemoryProperties
    let limits: VkPhysicalDeviceLimits
    /// What every GL depth, stencil and depth-stencil renderbuffer is made
    /// as: one combined format the device can attach.
    let depthStencilFormat: VkFormat

    /// Set only for a headless device, which this object made and destroys.
    private let ownedInstance: VkInstance?

    /// On the host engine's device and queue.
    public convenience init<N>(engine: VulkanRenderEngine<N>) throws {
        try self.init(
            instance: nil,
            physicalDevice: engine.physicalDevice,
            device: engine.device,
            queue: engine.graphicsQueue,
            queueFamilyIndex: engine.queueFamilyIndex
        )
    }

    private init(
        instance: VkInstance?,
        physicalDevice: VkPhysicalDevice,
        device: VkDevice,
        queue: VkQueue,
        queueFamilyIndex: UInt32
    ) throws {
        self.ownedInstance = instance
        self.physicalDevice = physicalDevice
        self.device = device
        self.queue = queue
        self.queueFamilyIndex = queueFamilyIndex

        var memory = VkPhysicalDeviceMemoryProperties()
        vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memory)
        self.memoryProperties = memory

        var properties = VkPhysicalDeviceProperties()
        vkGetPhysicalDeviceProperties(physicalDevice, &properties)
        self.limits = properties.limits

        var format: VkFormat?
        for candidate in [VK_FORMAT_D24_UNORM_S8_UINT, VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_D16_UNORM_S8_UINT] {
            var props = VkFormatProperties()
            vkGetPhysicalDeviceFormatProperties(physicalDevice, candidate, &props)
            let needed = VkFormatFeatureFlags(VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT.rawValue)
            if props.optimalTilingFeatures & needed == needed {
                format = candidate
                break
            }
        }
        guard let format else { throw KivyGLError.noDepthStencilFormat }
        self.depthStencilFormat = format

        var poolInfo = VkCommandPoolCreateInfo()
        poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
        poolInfo.flags = VkCommandPoolCreateFlags(VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT.rawValue)
        poolInfo.queueFamilyIndex = queueFamilyIndex
        var pool: VkCommandPool?
        guard vkCreateCommandPool(device, &poolInfo, nil, &pool) == VK_SUCCESS, let pool else {
            throw KivyGLError.commandPool
        }
        self.commandPool = pool
    }

    deinit {
        vkDeviceWaitIdle(device)
        vkDestroyCommandPool(device, commandPool, nil)
        if let ownedInstance {
            vkDestroyDevice(device, nil)
            vkDestroyInstance(ownedInstance, nil)
        }
    }

    /// A device of its own with no surface: Kivy renders and reads back
    /// with nothing on screen.
    public static func headless() throws -> KivyGLDevice {
        let instanceExtensions = enumerateInstanceExtensions()
        var extensions: [String] = []
        var flags: VkInstanceCreateFlags = 0
        if instanceExtensions.contains("VK_KHR_portability_enumeration") {
            extensions.append("VK_KHR_portability_enumeration")
            flags = VkInstanceCreateFlags(0x00000001) // ENUMERATE_PORTABILITY_BIT_KHR
        }
        if instanceExtensions.contains("VK_KHR_get_physical_device_properties2") {
            extensions.append("VK_KHR_get_physical_device_properties2")
        }

        var appInfo = VkApplicationInfo()
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
        appInfo.apiVersion = (1 << 22) | (2 << 12) // Vulkan 1.2
        var createdInstance: VkInstance?
        let instanceResult = withUnsafePointer(to: &appInfo) { appPtr in
            withCStringArray(extensions) { names, count in
                var info = VkInstanceCreateInfo()
                info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
                info.flags = flags
                info.pApplicationInfo = appPtr
                info.enabledExtensionCount = count
                info.ppEnabledExtensionNames = names
                return vkCreateInstance(&info, nil, &createdInstance)
            }
        }
        guard instanceResult == VK_SUCCESS, let instance = createdInstance else {
            throw KivyGLError.instance(instanceResult.rawValue)
        }

        var gpuCount: UInt32 = 0
        vkEnumeratePhysicalDevices(instance, &gpuCount, nil)
        var gpus = [VkPhysicalDevice?](repeating: nil, count: Int(gpuCount))
        vkEnumeratePhysicalDevices(instance, &gpuCount, &gpus)
        guard let gpu = gpus.compactMap({ $0 }).first else {
            vkDestroyInstance(instance, nil)
            throw KivyGLError.noPhysicalDevice
        }

        var familyCount: UInt32 = 0
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, nil)
        var families = [VkQueueFamilyProperties](repeating: VkQueueFamilyProperties(), count: Int(familyCount))
        vkGetPhysicalDeviceQueueFamilyProperties(gpu, &familyCount, &families)
        guard let family = families.firstIndex(where: {
            $0.queueFlags & VkQueueFlags(VK_QUEUE_GRAPHICS_BIT.rawValue) != 0
        }) else {
            vkDestroyInstance(instance, nil)
            throw KivyGLError.noQueue
        }

        var deviceExtensions: [String] = []
        if enumerateDeviceExtensions(gpu).contains("VK_KHR_portability_subset") {
            deviceExtensions.append("VK_KHR_portability_subset")
        }
        var priority: Float = 1
        var createdDevice: VkDevice?
        let deviceResult = withUnsafePointer(to: &priority) { priorityPtr in
            var queueInfo = VkDeviceQueueCreateInfo()
            queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
            queueInfo.queueFamilyIndex = UInt32(family)
            queueInfo.queueCount = 1
            queueInfo.pQueuePriorities = priorityPtr
            return withUnsafePointer(to: &queueInfo) { queuePtr in
                withCStringArray(deviceExtensions) { names, count in
                    var info = VkDeviceCreateInfo()
                    info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
                    info.queueCreateInfoCount = 1
                    info.pQueueCreateInfos = queuePtr
                    info.enabledExtensionCount = count
                    info.ppEnabledExtensionNames = names
                    return vkCreateDevice(gpu, &info, nil, &createdDevice)
                }
            }
        }
        guard deviceResult == VK_SUCCESS, let device = createdDevice else {
            vkDestroyInstance(instance, nil)
            throw KivyGLError.device(deviceResult.rawValue)
        }
        var queue: VkQueue?
        vkGetDeviceQueue(device, UInt32(family), 0, &queue)
        guard let queue else {
            vkDestroyDevice(device, nil)
            vkDestroyInstance(instance, nil)
            throw KivyGLError.noQueue
        }
        return try KivyGLDevice(
            instance: instance,
            physicalDevice: gpu,
            device: device,
            queue: queue,
            queueFamilyIndex: UInt32(family)
        )
    }

    // MARK: - Memory

    func memoryType(bits: UInt32, properties: VkMemoryPropertyFlags) -> UInt32? {
        var types = memoryProperties.memoryTypes
        return withUnsafeBytes(of: &types) { raw in
            let list = raw.bindMemory(to: VkMemoryType.self)
            for index in 0..<Int(memoryProperties.memoryTypeCount)
            where bits & (1 << UInt32(index)) != 0 && list[index].propertyFlags & properties == properties {
                return UInt32(index)
            }
            return nil
        }
    }

    func allocate(_ requirements: VkMemoryRequirements, properties: VkMemoryPropertyFlags) throws -> VkDeviceMemory {
        guard let type = memoryType(bits: requirements.memoryTypeBits, properties: properties) else {
            throw KivyGLError.memory
        }
        var info = VkMemoryAllocateInfo()
        info.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        info.allocationSize = requirements.size
        info.memoryTypeIndex = type
        var memory: VkDeviceMemory?
        guard vkAllocateMemory(device, &info, nil, &memory) == VK_SUCCESS, let memory else {
            throw KivyGLError.memory
        }
        return memory
    }

    // MARK: - Submitting

    /// Record, submit and wait — for work outside a frame (a readback).
    func submitAndWait(_ body: (VkCommandBuffer) -> Void) {
        var allocInfo = VkCommandBufferAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
        allocInfo.commandPool = commandPool
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY
        allocInfo.commandBufferCount = 1
        var cmd: VkCommandBuffer?
        vkAllocateCommandBuffers(device, &allocInfo, &cmd)
        guard let cmd else { return }
        var begin = VkCommandBufferBeginInfo()
        begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
        begin.flags = VkCommandBufferUsageFlags(VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT.rawValue)
        vkBeginCommandBuffer(cmd, &begin)
        body(cmd)
        vkEndCommandBuffer(cmd)
        var cmdOpt: VkCommandBuffer? = cmd
        withUnsafePointer(to: &cmdOpt) { cmdPtr in
            var submit = VkSubmitInfo()
            submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
            submit.commandBufferCount = 1
            submit.pCommandBuffers = cmdPtr
            vkQueueSubmit(queue, 1, &submit, nil)
        }
        vkQueueWaitIdle(queue)
        vkFreeCommandBuffers(device, commandPool, 1, &cmdOpt)
    }
}

// MARK: - Helpers

func withCStringArray<R>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt32) -> R
) -> R {
    let pointers = strings.map { strdup($0) }
    defer { pointers.forEach { free($0) } }
    let constPointers = pointers.map { UnsafePointer<CChar>($0) }
    return constPointers.withUnsafeBufferPointer { body($0.baseAddress, UInt32(strings.count)) }
}

private func enumerateInstanceExtensions() -> Set<String> {
    var count: UInt32 = 0
    vkEnumerateInstanceExtensionProperties(nil, &count, nil)
    var props = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(count))
    vkEnumerateInstanceExtensionProperties(nil, &count, &props)
    return Set(props.map(extensionName))
}

private func enumerateDeviceExtensions(_ gpu: VkPhysicalDevice) -> Set<String> {
    var count: UInt32 = 0
    vkEnumerateDeviceExtensionProperties(gpu, nil, &count, nil)
    var props = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(count))
    vkEnumerateDeviceExtensionProperties(gpu, nil, &count, &props)
    return Set(props.map(extensionName))
}

private func extensionName(_ prop: VkExtensionProperties) -> String {
    var name = prop.extensionName
    return withUnsafeBytes(of: &name) { raw in
        String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
    }
}
