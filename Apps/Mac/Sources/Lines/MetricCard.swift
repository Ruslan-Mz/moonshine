import MoonShineCore
import SwiftUI

/// `design/components.md` § MetricCard: this week's count, eight weekly bars with the current
/// one at half opacity in a dashed outline, and the mean of the four weeks before it as a
/// dashed rule, never a third series. Drawn with shapes, as the sparkline is.
struct MetricCard: View {
  enum Kind {
    case rhythm, progress
  }

  let kind: Kind
  let metric: LineDetailScreen.Metric
  let weeks: [Int]

  static let chartHeight: CGFloat = 96
  /// Two cards side by side fit the narrowest Line detail.
  static let minimumWidth: CGFloat = 230

  private var color: Color { kind == .rhythm ? Tokens.rhythm : Tokens.progress }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
        switch kind {
        case .rhythm:
          Text("Rhythm").fontWeight(.semibold)
          Text("sessions per week").foregroundStyle(.secondary)
        case .progress:
          Text("Progress").fontWeight(.semibold)
          Text("tasks done per week").foregroundStyle(.secondary)
        }
      }
      .font(.callout)
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(metric.thisWeek, format: .number).font(.system(size: 30, weight: .bold))
          .monospacedDigit()
        Text("this week so far").font(.caption).foregroundStyle(.secondary)
      }
      chart
    }
    .padding(14)
    .frame(minWidth: Self.minimumWidth, maxWidth: .infinity, alignment: .leading)
    .background(Tokens.card, in: RoundedRectangle(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.cardBorder))
  }

  private var chart: some View {
    let top = Double(max(metric.values.max() ?? 0, Int(metric.average.rounded(.up)), 1))
    let height = { (value: Double) in CGFloat(value / top) * Self.chartHeight }
    return VStack(spacing: 4) {
      HStack(alignment: .bottom, spacing: 8) {
        ForEach(Array(metric.values.enumerated()), id: \.offset) { index, value in
          let isPartial = index == metric.values.count - 1
          Rectangle().fill(color)
            .frame(height: height(Double(value)))
            .opacity(isPartial ? 0.5 : 1)
            .overlay {
              if isPartial {
                Rectangle().strokeBorder(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                  .frame(height: max(height(Double(value)), 2))
              }
            }
            .overlay(alignment: .top) {
              if isPartial {
                Text("\(value) so far").font(.caption2).foregroundStyle(.secondary)
                  .fixedSize().offset(y: -14)
              }
            }
        }
      }
      .frame(height: Self.chartHeight, alignment: .bottom)
      .overlay(alignment: .bottom) {
        HorizontalRule().stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
          .frame(height: 1)
          .overlay(alignment: .bottomTrailing) {
            Text("avg \(metric.average, format: .number.precision(.fractionLength(1)))")
              .font(.caption2).foregroundStyle(.secondary).fixedSize().offset(y: -3)
          }
          .offset(y: -height(metric.average))
      }
      .overlay(alignment: .bottom) { Rectangle().fill(.tertiary).frame(height: 0.5) }
      HStack(spacing: 8) {
        ForEach(weeks, id: \.self) { week in
          Text("W\(week)").font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(.top, 14)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Last 8 weeks"))
  }
}

/// A line across the middle of its frame, for a dashed rule.
private struct HorizontalRule: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    }
  }
}
