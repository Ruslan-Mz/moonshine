import MoonShineCore
import SwiftUI

// The held line removal (S4-4e), apart from the screens: outside the plain paths of auto-merge
// (scripts/guard/plain-rules.mjs), so a slice that edits a screen does not carry it in its
// context lines. A change here stays risky.

/// A held line removal as Today and the menu command see it (S4-4e).
struct LineRemovalHold {
  /// Remove was pressed for exactly the lines held now; they go with the next import.
  let isApproved: Bool
  let omniFocusClosed: Bool
  /// Approved, and an import since then could not read the budget note in full (S4-4d).
  var keptByIncompleteRead = false
  let approve: () -> Void

  /// The sentence under an approved notice (`design/copy.md` § Held line removal): with
  /// OmniFocus closed no import runs at all, so that sentence wins (owner, 2026-11-10).
  enum ApprovedNote: Equatable {
    case nextImport
    case onceOmniFocusIsOpen
    case notReadInFull
  }

  var approvedNote: ApprovedNote {
    if omniFocusClosed { return .onceOmniFocusIsOpen }
    return keptByIncompleteRead ? .notReadInFull : .nextImport
  }

  /// The notice names the first three, then `…`.
  static func names(_ lines: [TodayScreen.HeldLine]) -> String {
    let shown = lines.prefix(3).map {
      [$0.emoji, $0.name].compactMap { $0 }.joined(separator: " ")
    }
    return (shown + (lines.count > 3 ? ["…"] : [])).joined(separator: ", ")
  }

  /// The menu command acts while a hold stands unapproved; nil is nothing held.
  static func canApprove(_ removal: LineRemovalHold?) -> Bool {
    removal.map { !$0.isApproved } ?? false
  }
}

extension TodayScreen {
  /// A line the budget note no longer lists, kept until the owner removes it (S4-4e).
  struct HeldLine: Identifiable, Hashable {
    let id: LineID
    let emoji: String?
    let name: String
  }

  /// The held removal, in the issue's order; empty when nothing is held.
  static func heldLines(_ overview: Overview) -> [HeldLine] {
    overview.workspace.heldLineRemoval.map {
      HeldLine(id: $0.id, emoji: $0.emoji, name: $0.name)
    }
  }
}

extension FocusedValues {
  /// Nil when nothing is held.
  @Entry var lineRemoval: LineRemovalHold?
}

/// Remove in the View menu, next to Today's commands.
struct LineRemovalCommands: Commands {
  @FocusedValue(\.lineRemoval) private var removal

  var body: some Commands {
    CommandGroup(after: .sidebar) {
      Button("Remove Lines No Longer in the Budget Note") { removal?.approve() }
        .disabled(!LineRemovalHold.canApprove(removal))
    }
  }
}

/// Today in the detail column, with the held removal's notice above its table and its menu
/// command.
struct TodayDetail: View {
  let model: AppModel
  let overview: Overview

  var body: some View {
    let lines = TodayScreen.heldLines(overview)
    let removal = LineRemovalHold(
      isApproved: model.removalApproved, omniFocusClosed: model.omniFocusNote == .notRunning,
      keptByIncompleteRead: model.removalKept, approve: { model.approveHeldRemoval() })
    TodayContainer(overview: overview) {
      if !lines.isEmpty {
        LineRemovalNotice(lines: lines, removal: removal)
        Divider()
      }
    }
    .focusedSceneValue(\.lineRemoval, lines.isEmpty ? nil : removal)
  }
}

/// `design/components.md` § LineRemovalNotice: a calm fact above the table, with no dismiss;
/// the lines stay until Remove (S4-4e).
private struct LineRemovalNotice: View {
  let lines: [TodayScreen.HeldLine]
  let removal: LineRemovalHold

  private var names: String { LineRemovalHold.names(lines) }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: "info.circle").foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 4) {
        Text(
          "The budget note no longer lists \(lines.count) lines: \(names). They stay in MoonShine until you remove them."
        )
        if removal.isApproved {
          Group {
            switch removal.approvedNote {
            case .onceOmniFocusIsOpen:
              Text("They will be removed at the next import, once OmniFocus is open")
            case .notReadInFull:
              Text("The budget note was not read in full — they will be removed once it is")
            case .nextImport:
              Text("They will be removed at the next import")
            }
          }
          .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      if !removal.isApproved {
        Button("Remove \(lines.count) lines") { removal.approve() }
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Tokens.card)
  }
}
