import Foundation

public enum OOXMLValidator {
    public static func validate(_ data:Data)throws {
        guard data.count>=4,Array(data.prefix(4))==[0x50,0x4b,0x03,0x04] else { throw PackageDecryptError.corruptPackage }
        guard contains(data,"[Content_Types].xml"),contains(data,"_rels/.rels"),contains(data,"xl/workbook.xml") else {
            throw PackageDecryptError.corruptPackage
        }
    }
    private static func contains(_ data:Data,_ name:String)->Bool { data.range(of:Data(name.utf8)) != nil }
}
