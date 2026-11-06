import Foundation
import SQLiteStore
import Testing

@testable import moonshine_import

#if os(macOS)

  /// S4-4c-1: the tool's store sits next to the app's, in a temporary folder here.
  @Suite struct StorePathTests {
    @Test func theToolsRemovalLeavesTheAppStore() throws {
      let folder = FileManager.default.temporaryDirectory
        .appending(path: "data-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: folder) }
      let app = DataFolder.appStorePath(in: folder)
      let tool = DataFolder.measurementStorePath(in: folder)
      for path in [app, app + "-wal", app + "-shm", tool, tool + "-wal"] {
        #expect(FileManager.default.createFile(atPath: path, contents: Data("x".utf8)))
      }
      try MoonShineImport.removeStore(at: tool)
      for path in [app, app + "-wal", app + "-shm"] {
        #expect(FileManager.default.fileExists(atPath: path), "\(path)")
      }
      for path in [tool, tool + "-wal", tool + "-shm"] {
        #expect(!FileManager.default.fileExists(atPath: path), "\(path)")
      }
    }
  }

#endif
