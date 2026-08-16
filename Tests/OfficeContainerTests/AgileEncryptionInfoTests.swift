@testable import OfficeContainer
import XCTest

final class AgileEncryptionInfoTests:XCTestCase {
    func testParsesSupportedDescriptor() throws {
        let b16=Data(repeating:1,count:16).base64EncodedString(), b32=Data(repeating:2,count:32).base64EncodedString()
        let xml="""
        <encryption><keyData saltValue="\(b16)" hashAlgorithm="SHA512" cipherAlgorithm="AES" cipherChaining="ChainingModeCBC" keyBits="256" blockSize="16"/>
        <keyEncryptors><keyEncryptor><encryptedKey spinCount="100000" saltValue="\(b16)" hashAlgorithm="SHA512" cipherAlgorithm="AES" keyBits="256" encryptedVerifierHashInput="\(b16)" encryptedVerifierHashValue="\(b32)" encryptedKeyValue="\(b32)"/></keyEncryptor></keyEncryptors></encryption>
        """
        var stream=Data([4,0,4,0,0,0,0,0]); stream.append(Data(xml.utf8))
        let value=try AgileEncryptionInfo.parse(stream)
        XCTAssertEqual(value.spinCount,100_000); XCTAssertEqual(try value.passwordParameters.salt.count,16)
    }

    func testRejectsWrongVersionAndAlgorithm() {
        XCTAssertThrowsError(try AgileEncryptionInfo.parse(Data(repeating:0,count:20)))
    }
}
