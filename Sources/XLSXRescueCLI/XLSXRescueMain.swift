import Foundation
import MetalVerifier
import OfficeContainer
import OfficeCrypto
import Recovery

@main enum XLSXRescueMain {
    static func main() async {
        do { try await run(CommandRouter.parse(Array(CommandLine.arguments.dropFirst()))) }
        catch { fputs("Error: \(error)\n",stderr); Foundation.exit(2) }
    }

    static func run(_ command:RescueCommand) async throws {
        switch command {
        case .help: print(help)
        case .inspect(let path):
            let file=try CompoundFile.openReadOnly(URL(fileURLWithPath:path))
            let descriptor=try AgileEncryptionInfo.parse(file.readStream(named:"EncryptionInfo",maxBytes:1_048_576))
            let p=try descriptor.passwordParameters
            print("Office 2013 Agile Encryption\nSHA-512, AES-256-CBC, \(p.spinCount) iterations")
        case .recoverHash(let input,let options):
            let text=try readText(input,prompt:"Office verifier: ")
            try await recover(parameters:OfficeHashParser.parse(text),options:options)
        case .recover(let path,let options):
            let file=try CompoundFile.openReadOnly(URL(fileURLWithPath:path))
            let descriptor=try AgileEncryptionInfo.parse(file.readStream(named:"EncryptionInfo",maxBytes:1_048_576))
            try await recover(parameters:descriptor.passwordParameters,options:options)
        case .decrypt(let input,let passwordSource,let output,let overwrite):
            let password=try readText(passwordSource,prompt:"Password: ")
            let sourceURL=URL(fileURLWithPath:input), file=try CompoundFile.openReadOnly(sourceURL)
            let descriptor=try AgileEncryptionInfo.parse(file.readStream(named:"EncryptionInfo",maxBytes:1_048_576))
            let decrypted=try EncryptedPackage.decrypt(stream:file.readStream(named:"EncryptedPackage"),descriptor:descriptor,password:password)
            try OOXMLValidator.validate(decrypted)
            try TransactionalExporter.publish(decrypted,source:sourceURL,output:URL(fileURLWithPath:output),overwrite:overwrite)
            print("Decrypted copy written to \(output)")
        }
    }

    static func recover(parameters:Office2013Parameters,options:RecoveryOptions) async throws {
        let verifier=await BackendSelector.select(parameters:parameters)
        var sources:[AnyCandidateSource]=[]
        if let path=options.wordlist { sources.append(AnyCandidateSource(try WordlistCandidateSource(url:URL(fileURLWithPath:path)))) }
        else {
            let characters=Array(options.characterSet)
            for length in options.minimumLength...options.maximumLength {
                sources.append(AnyCandidateSource(try MaskCandidateSource(stageID:"bruteforce-\(length)",characterSets:Array(repeating:characters,count:length))))
            }
        }
        let identity=RecoveryIdentity(fingerprint:RecoveryIdentity.digest(parameters.salt+parameters.encryptedVerifier+parameters.encryptedVerifierHash),configurationDigest:"cli-v1")
        var tested:UInt64=0
        for source in sources {
            let result=try await RecoveryEngine(verifier:verifier,batchSize:256,progress:{ snapshot in
                fputs("\r\(snapshot.tested) tested, \(Int(snapshot.candidatesPerSecond))/s",stderr)
            }).run(source:source,parameters:parameters,identity:identity,initialTested:tested)
            switch result {
            case .found(let password):
                fputs("\n",stderr); print(options.showPassword ? "Password recovered: \(password)" : "Password recovered. Re-run with --show-password to display it."); return
            case .exhausted(let count): tested=count
            case .cancelled: Foundation.exit(130)
            }
        }
        print("Search exhausted after \(tested) candidates."); Foundation.exit(1)
    }

    static func readText(_ source:SecretSource,prompt:String)throws->String {
        switch source {
        case .standardInput:
            let bytes=try SecureInput.readSecret(prompt:prompt); guard let text=String(bytes:bytes,encoding:.utf8) else { throw SecureInputError.invalidUTF8 }; return text
        case .protectedFile(let path): return try SecureInput.readVerifier(from:URL(fileURLWithPath:path))
        }
    }

    static let help="""
    xlsx-rescue inspect <input.xlsx>
    xlsx-rescue recover-hash (--hash-stdin | --hash-file <path>) [--wordlist <path> | --charset <chars> --min-length N --max-length N] [--show-password]
    xlsx-rescue recover <input.xlsx> [recovery options]
    xlsx-rescue decrypt <input.xlsx> (--password-stdin | --password-file <path>) --output <copy.xlsx> [--overwrite]
    """
}
