import SwiftUI

/// `design/components.md` § AnchorStrip: the count covers every anchor of today, the chips
/// the first five. Read-only in phase 1; opening a task comes with the link opener (S4-5).
struct AnchorStrip: View {
  let anchors: [TodayScreen.Anchor]
  let total: Int
  let done: Int

  var body: some View {
    HStack(spacing: 8) {
      Text("Anchors").font(.system(size: 12, weight: .semibold))
      Text("\(done) of \(total) done")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
      ForEach(anchors) { AnchorChip(anchor: $0) }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
  }
}

private struct AnchorChip: View {
  let anchor: TodayScreen.Anchor

  /// The full title and the line emoji; the done state is the value.
  private var spoken: String {
    [anchor.title, anchor.emoji].compactMap { $0 }.joined(separator: " ")
  }

  @Environment(\.openTarget) private var openTarget

  /// Read-only: a click opens the task in OmniFocus (`components.md` § AnchorStrip).
  var body: some View {
    Button {
      openTarget(.task(anchor.id))
    } label: {
      HStack(spacing: 5) {
        Checkbox(isDone: anchor.isDone).font(.system(size: 14))
        Text(TodayFormat.chipTitle(anchor.title))
          .lineLimit(1)
          .foregroundStyle(anchor.isDone ? Tokens.doneText : Color.primary)
        if let emoji = anchor.emoji { Text(verbatim: emoji) }
      }
      .font(.system(size: 12.5))
      .padding(.vertical, 3)
      .padding(.horizontal, 8)
      .background(Tokens.chipFill, in: RoundedRectangle(cornerRadius: 6))
      .contentShape(RoundedRectangle(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    // The full title, where the chip shows it cut (owner, 2026-11-24); never a catalog key.
    .help(Text(verbatim: anchor.title))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: spoken))
    .accessibilityValue(anchor.isDone ? Text("Completed") : Text("Not completed"))
    .accessibilityHint(Text("Opens in OmniFocus"))
    .accessibilityAddTraits(.isButton)
  }
}
