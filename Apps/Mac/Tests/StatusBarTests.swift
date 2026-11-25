import Foundation
import MoonShineCore
import Testing

@testable import MoonShineMac

/// The status bar's Live notes as values (`design/screens/settings.md` § Status bar).
struct StatusBarTests {
  static func workspace(_ kinds: VaultProblem.Kind...) -> Workspace {
    Workspace(timeZone: .gmt, issues: kinds.map { .vaultWide(VaultProblem($0)) })
  }

  static func notes(
    _ source: AppModel.Source = .live, workspace: Workspace? = Self.workspace(),
    vault: VaultLine = .folder("Vault"), omniFocus: SourceFeed.OmniFocusNote? = nil,
    mapping: MappingState? = .missing
  ) -> [LiveNote] {
    LiveNote.notes(
      source: source, workspace: workspace, vault: vault, omniFocusNote: omniFocus,
      mapping: mapping)
  }

  /// The words of the Settings row, while the vault was not read for the workspace shown.
  @Test func theVaultNoteNamesTheReason() {
    #expect(
      Self.notes(workspace: Self.workspace(.vaultNotChosen), vault: .notChosen) == [
        .vault(.notChosen)
      ])
    #expect(
      Self.notes(workspace: Self.workspace(.vaultUnreadable), vault: .unreadable) == [
        .vault(.unreadable)
      ])
    #expect(
      Self.notes(workspace: Self.workspace(.vaultTooLarge), vault: .tooLarge(20_000)) == [
        .vault(.tooLarge)
      ])
    #expect(Self.notes(workspace: nil, vault: .notReadYet) == [.vault(.notReadYet)])
  }

  /// The condition is unchanged: a read vault has no note, whatever the row says.
  @Test func aReadVaultHasNoNote() {
    #expect(Self.notes().isEmpty)
    #expect(Self.notes(vault: .notReadYet).isEmpty)
    #expect(Self.notes(workspace: Self.workspace(.budgetNoteMissing)).isEmpty)
  }

  @Test func anImportThatCouldNotReadOmniFocusIsSaid() {
    for kind in [ImportFailure.permissionDenied, .timedOut, .invalidSnapshot, .partialSnapshot] {
      #expect(Self.notes(omniFocus: .failure(kind)) == [.omniFocusUnreadable])
    }
    #expect(Self.notes(omniFocus: .failure(.other)) == [.importUnfinished])
  }

  /// Not running and an invalid file keep their own notes; nothing is said twice.
  @Test func notRunningAndAnInvalidFileKeepTheirNotes() {
    #expect(Self.notes(omniFocus: .notRunning) == [.notRunning])
    #expect(
      Self.notes(omniFocus: .failure(.mappingInvalid), mapping: .invalid) == [.mappingInvalid])
  }

  /// With nothing shown, Today's placeholder already says it.
  @Test func withNothingShownNoOmniFocusNote() {
    for note in [SourceFeed.OmniFocusNote.failure(.timedOut), .notRunning] {
      let notes = Self.notes(workspace: nil, vault: .notReadYet, omniFocus: note)
      #expect(notes == [.vault(.notReadYet)])
    }
  }

  @Test func demoHasNoNotes() {
    #expect(
      Self.notes(
        .demo, workspace: nil, vault: .notReadInDemo, omniFocus: .failure(.timedOut),
        mapping: .invalid
      ).isEmpty)
  }

  @Test func theOrderIsOmniFocusThenTheFileThenTheVault() {
    #expect(
      Self.notes(
        workspace: Self.workspace(.vaultUnreadable), vault: .unreadable,
        omniFocus: .failure(.timedOut), mapping: .invalid)
        == [.omniFocusUnreadable, .mappingInvalid, .vault(.unreadable)])
  }
}
