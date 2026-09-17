import Foundation
import Metal
import OfficeCrypto
import Recovery

public struct SelectedBackend: Sendable {
    public let verifier: any CandidateVerifier
    public let label: String
    public let batchSize: Int

    public init(verifier: any CandidateVerifier, label: String, batchSize: Int = 256) {
        self.verifier = verifier
        self.label = label
        self.batchSize = batchSize
    }
}

public enum BackendSelector {
    public static func select(parameters: Office2013Parameters) async -> any CandidateVerifier {
        await selection(parameters: parameters).verifier
    }

    public static func selection(parameters: Office2013Parameters) async -> SelectedBackend {
        guard let metal = try? MetalOffice2013Verifier() else {
            return .init(verifier: CPUOffice2013BatchVerifier(), label: "CPU", batchSize: 256)
        }
        let probe=["hashcat","definitely-wrong"]
        let cpu=try? await CPUOffice2013BatchVerifier().matchingIndex(in:probe,parameters:parameters)
        let gpu=try? await metal.matchingIndex(in:probe,parameters:parameters)
        guard cpu == gpu else {
            return .init(verifier: CPUOffice2013BatchVerifier(), label: "CPU", batchSize: 256)
        }
        return .init(verifier: metal, label: "Metal", batchSize: 4096)
    }
}
