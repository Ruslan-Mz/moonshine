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

  var body: some View {
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
    .accessibilityElement(children: .combine)
  }
}
