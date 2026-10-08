import Foundation
import Testing

@testable import moonshine_import

#if os(macOS)

  @Suite struct VaultPathsTests {
    @Test func vaultPathsRefusesOutputThatIsNotATerminal() throws {
      let pipe = Pipe()
      let refusal = try #require(
        MoonShineImport.pathsRefusal(output: pipe.fileHandleForWriting.fileDescriptor))
      #expect(refusal.contains("owner's own terminal"))
    }

    @Test func vaultPathsRefusesOutputRedirectedToAFile() throws {
      let url = FileManager.default.temporaryDirectory
        .appending(path: "paths-\(UUID().uuidString).txt")
      #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
      defer { try? FileManager.default.removeItem(at: url) }
      let file = try FileHandle(forWritingTo: url)
      defer { try? file.close() }
      #expect(MoonShineImport.pathsRefusal(output: file.fileDescriptor) != nil)
    }
  }

#endif
