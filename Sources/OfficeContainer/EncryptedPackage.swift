import CommonCrypto
import Foundation
import OfficeCrypto

public enum PackageDecryptError: Error, Equatable {
    case wrongPassword
    case corruptPackage
    case cipherFailure(Int32)
    case outputExists
    case sourceEqualsOutput
}

public enum EncryptedPackage {
    private static let packageKeyBlock=Data([0x14,0x6e,0x0b,0xe7,0xab,0xac,0xd0,0xd6])

    public static func decrypt(stream:Data, descriptor:AgileEncryptionDescriptor, password:String) throws -> Data {
        let parameters=try descriptor.passwordParameters
        guard try CPUOffice2013Verifier.verify(candidate:password,against:parameters) else { throw PackageDecryptError.wrongPassword }
        let digest=try Office2013KDF.spinDigest(password:password,parameters:parameters)
        let wrappingKey=Office2013KDF.deriveKey(spinDigest:digest,blockKey:packageKeyBlock)
        let packageKey=try aesCBC(descriptor.encryptedKeyValue,key:wrappingKey,iv:descriptor.passwordSalt).prefix(32)
        guard stream.count>=8 else { throw PackageDecryptError.corruptPackage }
        let plainLength=stream.withUnsafeBytes{$0.loadUnaligned(as:UInt64.self).littleEndian}
        guard plainLength<=UInt64(Int.max), plainLength<=UInt64(stream.count)*2 else { throw PackageDecryptError.corruptPackage }
        var result=Data(capacity:Int(plainLength)), offset=8, segment:UInt32=0
        while result.count<Int(plainLength) {
            let plainCount=min(4096,Int(plainLength)-result.count)
            let cipherCount=((plainCount+15)/16)*16
            guard offset+cipherCount<=stream.count else { throw PackageDecryptError.corruptPackage }
            var ivInput=Data(); ivInput.append(descriptor.keyDataSalt)
            var number=segment.littleEndian; withUnsafeBytes(of:&number){ivInput.append(contentsOf:$0)}
            let iv=Office2013KDF.sha512(ivInput).prefix(16)
            let block=try aesCBC(stream[offset..<(offset+cipherCount)],key:Data(packageKey),iv:Data(iv))
            result.append(block.prefix(plainCount)); offset+=cipherCount; segment+=1
        }
        guard result.count==Int(plainLength) else { throw PackageDecryptError.corruptPackage }
        return result
    }

    private static func aesCBC(_ input:Data,key:Data,iv:Data)throws->Data {
        var output=Data(count:input.count), written=0; let count=output.count
        let status:CCCryptorStatus=output.withUnsafeMutableBytes{o in input.withUnsafeBytes{i in key.withUnsafeBytes{k in iv.withUnsafeBytes{v in
            CCCrypt(CCOperation(kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),CCOptions(0),k.baseAddress,key.count,v.baseAddress,i.baseAddress,input.count,o.baseAddress,count,&written)
        }}}}
        guard status==kCCSuccess,written==count else { throw PackageDecryptError.cipherFailure(status) }
        return output
    }
}

public enum TransactionalExporter {
    public static func publish(_ data:Data, source:URL, output:URL, overwrite:Bool=false)throws {
        let sourcePath=source.standardizedFileURL.resolvingSymlinksInPath().path
        let outputPath=output.standardizedFileURL.resolvingSymlinksInPath().path
        guard sourcePath != outputPath else { throw PackageDecryptError.sourceEqualsOutput }
        let destinationExists=FileManager.default.fileExists(atPath:output.path)
        if destinationExists && !overwrite { throw PackageDecryptError.outputExists }
        let temp=output.deletingLastPathComponent().appendingPathComponent(".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath:temp.path,contents:nil,attributes:[.posixPermissions:0o600])
        do {
            let handle=try FileHandle(forWritingTo:temp); try handle.write(contentsOf:data); try handle.synchronize(); try handle.close()
            if destinationExists { _ = try FileManager.default.replaceItemAt(output,withItemAt:temp) }
            else { try FileManager.default.moveItem(at:temp,to:output) }
        } catch { try? FileManager.default.removeItem(at:temp); throw error }
    }
}
