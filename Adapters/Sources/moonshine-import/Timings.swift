import Foundation
import MoonShineCore

/// The report of `moonshine-import timings` (S4-4c-3; ADR-0011): counts and seconds only,
/// never an instant, an id or a path. Signal → landing (the wait plus the import) is the
/// headline; the import's own time and OmniFocus' held time stand beside it.
enum Timings {
  static let target: Duration = .seconds(5)

  static func lines(_ runs: [ImportRun], targetSince: Date) -> [String] {
    var lines: [String] = []
    for trigger in ImportTrigger.allCases {
      let mine = runs.filter { $0.trigger == trigger }
      guard !mine.isEmpty else {
        lines.append("\(trigger.rawValue): runs 0")
        continue
      }
      let committed = mine.filter(\.isCommitted)
      lines.append(
        "\(trigger.rawValue): runs \(mine.count) · committed \(committed.count) · "
          + notCommitted(mine))
      let unmeasured = committed.filter { $0.waited == nil || $0.duration == nil }.count
      let unreported = committed.filter { $0.providerHeld == nil }.count
      lines.append(
        "  signal → landing \(spread(committed.compactMap(\.landing))) · import "
          + spread(committed.compactMap(\.duration)) + " · OmniFocus held "
          + spread(committed.compactMap(\.providerHeld)) + " · \(unreported) not reported"
          + " · \(unmeasured) not measured")
    }
    // The target's runs: resign-active from the cutoff only (owner, 2026-11-09).
    let targeted = runs.filter { $0.trigger == .resignActive && $0.startedAt >= targetSince }
    let landings = targeted.filter(\.isCommitted).compactMap(\.landing)
    let targetUnmeasured = targeted.filter(\.isCommitted).count - landings.count
    let day = targetSince.formatted(
      Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
    lines.append(
      "target (resign-active since \(day)): \(targeted.filter(\.isCommitted).count) committed"
        + " · signal → landing median \(seconds(percentile(50, landings)))"
        + " · over 5 s: \(landings.filter { $0 > target }.count)"
        + " · not measured \(targetUnmeasured)"
        + " · not committed \(targeted.count - targeted.filter(\.isCommitted).count)")
    // The store reads these as not measured (owner, 2026-11-10); they are counted above too.
    lines.append(
      "ended before they started (clock set back): "
        + "\(runs.filter { $0.finishedAt < $0.startedAt }.count)")
    return lines
  }

  /// `not committed n (kind k, …)`: kinds by name, only those that occurred.
  static func notCommitted(_ runs: [ImportRun]) -> String {
    var kinds: [String: Int] = [:]
    for run in runs {
      if case .failed(let kind) = run.outcome { kinds[kind.rawValue, default: 0] += 1 }
    }
    let total = kinds.values.reduce(0, +)
    guard total > 0 else { return "not committed 0" }
    return "not committed \(total) ("
      + kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
      + ")"
  }

  static func spread(_ values: [Duration]) -> String {
    "median \(seconds(percentile(50, values))) · p90 \(seconds(percentile(90, values)))"
  }

  /// Nearest rank; nil for an empty set.
  static func percentile(_ p: Int, _ values: [Duration]) -> Duration? {
    guard !values.isEmpty else { return nil }
    let rank = (p * values.count + 99) / 100
    return values.sorted()[max(rank, 1) - 1]
  }

  static func seconds(_ duration: Duration?) -> String {
    guard let duration else { return "–" }
    let seconds =
      Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    return "\(String(format: "%.2f", seconds)) s"
  }
}

extension ImportRun {
  fileprivate var isCommitted: Bool {
    if case .committed = outcome { true } else { false }
  }

  /// From the signal to the store's write; nil when either part was not measured.
  fileprivate var landing: Duration? {
    guard let waited, let duration else { return nil }
    return waited + duration
  }
}
