import Foundation
import Metal
import CoreGraphics

struct TerminalRGB: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    static let background = TerminalRGB(r: 12, g: 17, b: 28)
    static let panel = TerminalRGB(r: 17, g: 25, b: 39)
    static let text = TerminalRGB(r: 222, g: 234, b: 244)
    static let muted = TerminalRGB(r: 130, g: 154, b: 177)
    static let cyan = TerminalRGB(r: 84, g: 224, b: 215)
    static let purple = TerminalRGB(r: 181, g: 156, b: 255)
    static let warning = TerminalRGB(r: 255, g: 197, b: 112)
}

final class TerminalAnimation {
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private var output: MTLBuffer?
    private(set) var description: String
    private(set) var gpuFrames = 0

    init(mode: String) throws {
        guard mode != "cpu" else {
            device = nil; queue = nil; pipeline = nil
            description = "CPU · motion renderer"
            return
        }
        do {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                throw TerminalOptions.invalid("No Metal device is available")
            }
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            guard let function = library.makeFunction(name: "aurora") else { throw TerminalOptions.invalid("Metal kernel unavailable") }
            pipeline = try device.makeComputePipelineState(function: function)
            self.device = device
            self.queue = queue
            description = "Metal GPU · \(device.name)"
        } catch {
            if mode == "gpu" { throw error }
            device = nil; queue = nil; pipeline = nil
            description = "CPU fallback · \(error.localizedDescription)"
        }
    }

    func colors(width: Int, height: Int, time: Float) throws -> [TerminalRGB] {
        let count = width * height
        guard count > 0 else { return [] }
        guard let device, let queue, let pipeline else {
            return (0..<count).map { index in
                Self.color(x: Float(index % width) / Float(width), y: Float(index / width) / Float(height), time: time)
            }
        }
        let length = count * MemoryLayout<SIMD4<Float>>.stride
        if output == nil || output!.length < length { output = device.makeBuffer(length: length, options: .storageModeShared) }
        guard let output, let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw TerminalOptions.invalid("Could not allocate a Metal frame")
        }
        var dimensions = SIMD2<UInt32>(UInt32(width), UInt32(height))
        var frameTime = time
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(output, offset: 0, index: 0)
        encoder.setBytes(&dimensions, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 1)
        encoder.setBytes(&frameTime, length: MemoryLayout<Float>.stride, index: 2)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: min(width, pipeline.threadExecutionWidth), height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw command.error ?? TerminalOptions.invalid("Metal frame failed") }
        gpuFrames += 1
        let values = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
        return (0..<count).map { index in
            let value = values[index]
            return TerminalRGB(r: UInt8(clamping: Int(value.x)), g: UInt8(clamping: Int(value.y)), b: UInt8(clamping: Int(value.z)))
        }
    }

    private static func color(x: Float, y: Float, time: Float) -> TerminalRGB {
        let wave = sin(x * 7 + time * 0.7 + sin(y * 5 - time * 0.3)) * 0.5 + 0.5
        let glow = pow(max(0, 1 - abs(y - (0.5 + sin(x * 4 + time * 0.4) * 0.25)) * 2), 2)
        return TerminalRGB(r: UInt8(14 + wave * glow * 38), g: UInt8(22 + glow * 64), b: UInt8(38 + wave * 32 + glow * 42))
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void aurora(device float4 *out [[buffer(0)]], constant uint2 &size [[buffer(1)]],
                       constant float &time [[buffer(2)]], uint2 p [[thread_position_in_grid]]) {
        if (p.x >= size.x || p.y >= size.y) return;
        float x = float(p.x) / float(size.x), y = float(p.y) / float(size.y);
        float wave = sin(x * 7 + time * 0.7 + sin(y * 5 - time * 0.3)) * 0.5 + 0.5;
        float glow = pow(max(0.0f, 1 - abs(y - (0.5 + sin(x * 4 + time * 0.4) * 0.25)) * 2), 2.0f);
        out[p.y * size.x + p.x] = float4(14 + wave * glow * 38, 22 + glow * 64, 38 + wave * 32 + glow * 42, 255);
    }
    """
}
