import Foundation
import MoonShineCore
import Testing

@testable import SQLiteStore

/// S4-4c-1: the data folder, always under a temporary base here (CLAUDE.md rule 5).
@Suite struct DataFolderTests {
  func temporaryBase() throws -> URL {
    let base = FileManager.default.temporaryDirectory.appending(path: "base-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
    return base
  }

  @Test func theFolderIsCreatedBeforeTheStoreOpens() async throws {
    let base = try temporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let folder = try DataFolder.create(base: base)
    #expect(folder == base.appending(path: "MoonShine", directoryHint: .isDirectory))
    let store = try SQLiteStore(path: DataFolder.appStorePath(in: folder))
    _ = try await store.identityMap()
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "MoonShine.sqlite").path))
    // A second create finds the folder and keeps what it holds.
    #expect(try DataFolder.create(base: base) == folder)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "MoonShine.sqlite").path))
  }

  @Test func aFileWhereTheFolderGoesThrowsAndOpensNothing() throws {
    let base = try temporaryBase()
    defer { try? FileManager.default.removeItem(at: base) }
    let blocker = base.appending(path: "MoonShine")
    #expect(FileManager.default.createFile(atPath: blocker.path, contents: Data()))
    #expect(throws: (any Error).self) { try DataFolder.create(base: base) }
    var isFolder: ObjCBool = true
    #expect(FileManager.default.fileExists(atPath: blocker.path, isDirectory: &isFolder))
    #expect(!isFolder.boolValue)
  }

  @Test func theAppAndTheMeasurementToolUseTwoFiles() {
    let folder = URL(filePath: "/base/MoonShine/", directoryHint: .isDirectory)
    #expect(DataFolder.appStorePath(in: folder) == "/base/MoonShine/MoonShine.sqlite")
    #expect(DataFolder.measurementStorePath(in: folder) == "/base/MoonShine/moonshine-import.sqlite")
  }
}
