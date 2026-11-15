import MoonShineCore
import SwiftUI

/// `design/components.md` § Sparkline: eight weekly pairs, rhythm then progress, never summed,
/// on a hairline baseline; the current week on a dashed backdrop at 0.6 opacity. Drawn with
/// shapes, not Swift Charts, so the 5 · 1 · 5 and 6 pt geometry is exact. The empty 12 pt
/// track under it is the third track of `design/screens/lines.md` § My take (phase 2).
struct Sparkline: View {
  let points: [WeekPoint]

  var body: some View {
    let heights = LinesFormat.bars(points.flatMap { [$0.counts.rhythm, $0.counts.progress] })
    HStack(alignment: .bottom, spacing: 6) {
      ForEach(Array(points.enumerated()), id: \.offset) { index, point in
        HStack(alignment: .bottom, spacing: 1) {
          bar(heights[2 * index], Tokens.rhythm)
          bar(heights[2 * index + 1], Tokens.progress)
        }
        .frame(height: LinesFormat.chartHeight, alignment: .bottom)
        .opacity(point.isPartial ? 0.6 : 1)
        .background {
          if point.isPartial {
            RoundedRectangle(cornerRadius: 2)
              .fill(Tokens.chipFill)
              .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
              .padding(-2)
          }
        }
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(.tertiary).frame(height: 0.5)
    }
    .padding(.bottom, 12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Last 8 weeks"))
  }

  private func bar(_ height: Double, _ color: Color) -> some View {
    Rectangle().fill(color).frame(width: 5, height: height)
  }
}
