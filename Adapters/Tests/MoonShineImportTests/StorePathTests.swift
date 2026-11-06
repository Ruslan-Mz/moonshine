import Foundation
import SQLiteStore
import Testing

@testable import moonshine_import

#if os(macOS)

  /// S4-4c-1: the tool's store sits next to the app's, under a temporary base here.
  @Suite struct StorePathTests {
    @Test func fullPicksItsOwnStoreAndItsRemovalLeavesTheAppStore() throws {
      let base = FileManager.default.temporaryDirectory
        .appending(path: "base-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: base) }
      let tool = try MoonShineImport.storePath(base: base)
      let folder = DataFolder.url(base: base)
      let app = DataFolder.appStorePath(in: folder)
      #expect(tool == DataFolder.measurementStorePath(in: folder))
      #expect(tool != app)
      for path in [app, app + "-wal", app + "-shm", tool, tool + "-wal"] {
        #expect(FileManager.default.createFile(atPath: path, contents: Data("x".utf8)))
      }
      try MoonShineImport.removeStore(at: try MoonShineImport.storePath(base: base))
      for path in [app, app + "-wal", app + "-shm"] {
        #expect(FileManager.default.fileExists(atPath: path), "\(path)")
      }
      for path in [tool, tool + "-wal", tool + "-shm"] {
        #expect(!FileManager.default.fileExists(atPath: path), "\(path)")
      }
    }
  }

#endif
