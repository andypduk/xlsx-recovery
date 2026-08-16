import Foundation
import Metal
import OfficeCrypto
import Recovery

public enum BackendSelector {
    public static func select(parameters: Office2013Parameters) async -> any CandidateVerifier {
        guard let metal = try? MetalOffice2013Verifier() else { return CPUOffice2013BatchVerifier() }
        let probe=["hashcat","definitely-wrong"]
        let cpu=try? await CPUOffice2013BatchVerifier().matchingIndex(in:probe,parameters:parameters)
        let gpu=try? await metal.matchingIndex(in:probe,parameters:parameters)
        guard cpu == gpu else { return CPUOffice2013BatchVerifier() }
        return metal
    }
}
