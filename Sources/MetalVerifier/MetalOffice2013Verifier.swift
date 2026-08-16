import Foundation
import Metal
import OfficeCrypto
import Recovery

public enum MetalVerifierError: Error { case unavailable, library, function, pipeline, command, candidateTooLong }

public final class MetalOffice2013Verifier: CandidateVerifier, @unchecked Sendable {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw MetalVerifierError.unavailable }
        guard let url = Bundle.module.url(forResource: "Office2013KDF", withExtension: "metal"),
              let source = try? String(contentsOf: url, encoding: .utf8),
              let library = try? device.makeLibrary(source: source, options: nil) else { throw MetalVerifierError.library }
        guard let function = library.makeFunction(name: "office2013_kdf") else { throw MetalVerifierError.function }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else { throw MetalVerifierError.pipeline }
        self.device=device; self.queue=queue; self.pipeline=pipeline
    }

    public func matchingIndex(in candidates: [String], parameters: Office2013Parameters) async throws -> Int? {
        guard !candidates.isEmpty else { return nil }
        var packed=Data(count:candidates.count*64), lengths=[UInt32](); lengths.reserveCapacity(candidates.count)
        for (index,candidate) in candidates.enumerated() {
            let bytes=Office2013KDF.passwordBytes(candidate)
            if bytes.count>64 {
                return try await CPUOffice2013BatchVerifier().matchingIndex(in:candidates,parameters:parameters)
            }
            lengths.append(UInt32(bytes.count))
            packed.replaceSubrange(index*64..<(index*64+bytes.count), with:bytes)
        }
        guard let passwordBuffer=device.makeBuffer(bytes:(packed as NSData).bytes,length:packed.count,options:.storageModeShared),
              let lengthBuffer=device.makeBuffer(bytes:&lengths,length:lengths.count*4,options:.storageModeShared),
              let saltBuffer=device.makeBuffer(bytes:(parameters.salt as NSData).bytes,length:16,options:.storageModeShared),
              let output=device.makeBuffer(length:candidates.count*64,options:.storageModeShared),
              let command=queue.makeCommandBuffer(), let encoder=command.makeComputeCommandEncoder() else { throw MetalVerifierError.command }
        var spins=UInt32(parameters.spinCount)
        let spinBuffer=device.makeBuffer(bytes:&spins,length:4,options:.storageModeShared)!
        defer {
            memset(output.contents(),0,output.length)
            memset(passwordBuffer.contents(),0,passwordBuffer.length)
            packed.resetBytes(in: packed.startIndex..<packed.endIndex)
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(passwordBuffer,offset:0,index:0); encoder.setBuffer(lengthBuffer,offset:0,index:1)
        encoder.setBuffer(saltBuffer,offset:0,index:2); encoder.setBuffer(spinBuffer,offset:0,index:3); encoder.setBuffer(output,offset:0,index:4)
        let width=min(pipeline.maxTotalThreadsPerThreadgroup,64)
        encoder.dispatchThreads(MTLSize(width:candidates.count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:width,height:1,depth:1))
        encoder.endEncoding(); command.commit(); await command.completed()
        guard command.status == .completed else { throw MetalVerifierError.command }
        for index in candidates.indices {
            let words=output.contents().advanced(by:index*64).assumingMemoryBound(to:UInt64.self)
            var digest=Data(capacity:64)
            for i in 0..<8 { var value=words[i].bigEndian; withUnsafeBytes(of:&value){ digest.append(contentsOf:$0) } }
            if try CPUOffice2013Verifier.verify(spinDigest:digest,against:parameters) { return index }
        }
        return nil
    }
}
