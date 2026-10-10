import Foundation
import Testing

@testable import MoonShineCore

@Suite struct EntityIDTests {
  private func bytes(_ id: TaskItemID) -> [UInt8] {
    withUnsafeBytes(of: id.uuid.uuid) { Array($0) }
  }

  @Test func hasVersion7AndRFCVariant() {
    let id = TaskItemID.generate(at: Date(timeIntervalSince1970: 1_790_000_000))
    let b = bytes(id)
    #expect(b[6] >> 4 == 0x7)
    #expect(b[8] >> 6 == 0b10)
  }

  @Test func encodesUnixMillisecondsInFirst48Bits() {
    let date = Date(timeIntervalSince1970: 1_790_000_000.123)
    let id = TaskItemID.generate(at: date)
    #expect(id.timestampMilliseconds == 1_790_000_000_123)
  }

  @Test func laterIDsSortAfterEarlierOnes() {
    let earlier = TaskItemID.generate(at: Date(timeIntervalSince1970: 1_790_000_000))
    let later = TaskItemID.generate(at: Date(timeIntervalSince1970: 1_790_000_000.002))
    #expect(earlier < later)
  }

  @Test func twoIDsInTheSameMillisecondDiffer() {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(TaskItemID.generate(at: date) != TaskItemID.generate(at: date))
  }
}

@Suite struct IdentityMapTests {
  private let ref = ExternalRef(
    provider: .omnifocus, externalId: "abc", lastSeen: Date(timeIntervalSince1970: 0))

  @Test func sameRefGetsSameIDOnEveryLookup() {
    var map = IdentityMap()
    let first: TaskItemID = map.id(for: ref, now: Date())
    let second: TaskItemID = map.id(for: ref, now: Date())
    #expect(first == second)
  }

  @Test func sameExternalIDOfDifferentKindsGetsDifferentIDs() {
    // OmniFocus projects and their root tasks share a primary key.
    var map = IdentityMap()
    let task: TaskItemID = map.id(for: ref, now: Date())
    let project: ProjectID = map.id(for: ref, now: Date())
    #expect(task.uuid != project.uuid)
  }

  /// The six names are what stores hold: changing one orphans every identity of that kind.
  @Test func theKindNamesAreWrittenOutAndPinned() {
    #expect(
      EntityKind.allCases.map(\.rawValue) == ["line", "note", "artifact", "tag", "project", "task"])
    #expect(Line.kind == .line && NoteRef.kind == .note && Artifact.kind == .artifact)
    #expect(Tag.kind == .tag && Project.kind == .project && TaskItem.kind == .task)
  }

  @Test func theMapKeysByTheWrittenKindNotTheTypeName() {
    var map = IdentityMap()
    let _: TaskItemID = map.id(for: ref, now: Date())
    let _: NoteID = map.id(for: ref, now: Date())
    #expect(Set(map.entries.keys.map(\.kind)) == ["task", "note"])
  }

  @Test func lastSeenDoesNotAffectIdentity() {
    var map = IdentityMap()
    let first: TaskItemID = map.id(for: ref, now: Date())
    let later = ExternalRef(provider: .omnifocus, externalId: "abc", lastSeen: Date())
    let second: TaskItemID = map.id(for: later, now: Date())
    #expect(first == second)
  }
}
