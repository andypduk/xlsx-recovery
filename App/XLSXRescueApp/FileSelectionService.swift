import AppKit
import UniformTypeIdentifiers

@MainActor
enum FileSelectionService {
    static func chooseWorkbook() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an encrypted Excel workbook"
        panel.prompt = "Choose Workbook"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseWordlist() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose a password wordlist"
        panel.prompt = "Choose Wordlist"
        panel.allowedContentTypes = [.plainText, .text, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportDestination(source: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save unencrypted workbook copy"
        panel.prompt = "Save Copy"
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-unlocked.xlsx"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
