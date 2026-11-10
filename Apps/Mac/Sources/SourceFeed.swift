import AppKit
import Foundation
import MoonShineCore
import Observation

/// What one source shows: its store's Today, its imports and OmniFocus' state. Built once per
/// source and process, so a store keeps one writer (ADR-0002) and the coordinator one consumer.
@MainActor @Observable
final class SourceFeed {
  /// What the status bar and Today say about OmniFocus, beside or instead of the data.
  enum OmniFocusNote: Equatable {
    case notRunning
    case failure(ImportFailure)
  }

  private(set) var state: AppModel.State = .loading
  /// The last committed import; nil before one, or when it could not be read.
  private(set) var lastImport: ImportRun?
  /// An import is running ("Updating…").
  private(set) var isImporting = false
  /// Imports that ended, committed or not.
  private(set) var importOutcomes = 0
  /// Nil until the coordinator knows it.
  private(set) var omniFocusState: OmniFocusState?
  /// The kind of the last import that did not commit; a commit clears it. The store's last
  /// attempt seeds it at the start, so a relaunch still says why (S4-4c-3).
  private(set) var lastFailure: ImportFailure?
  /// What the import service holds as approved for removal, read after Remove and after every
  /// import (S4-4e).
  private(set) var approvedLineRemovals: Set<LineKey> = []
  /// Nil when it could not be built: Today is then unavailable.
  let environment: AppEnvironment?
  private var starting: Task<Void, Never>?
  private var consumer: Task<Void, Never>?
  /// The last call to the coordinator from `pause` or `refresh`, so they reach it in order.
  private var control: Task<Void, Never>?
  private var observers: [any NSObjectProtocol] = []

  init(environment: AppEnvironment?) {
    self.environment = environment
  }

  /// The clock the import was timed by, so "updated …" counts from the same origin.
  var clock: ImportClock { environment?.clock ?? .system }

  /// A quit seen only by an import says not running until OmniFocus is seen running again.
  var omniFocusNote: OmniFocusNote? {
    if omniFocusState == .notRunning || lastFailure == .providerNotRunning { return .notRunning }
    return lastFailure.map { .failure($0) }
  }

  /// The lines whose removal waits for the owner, as the workspace shown says (S4-4e).
  var heldLineRemoval: [Line] {
    if case .loaded(let overview) = state { overview.workspace.heldLineRemoval } else { [] }
  }

  /// Remove was pressed for exactly the set held now; it lands with the next import.
  var removalApproved: Bool {
    let held = heldLineRemoval
    return !held.isEmpty && Set(held.map(\.key)) == approvedLineRemovals
  }

  /// The store holds data that could not be read: never "not read yet" (`TodayPlaceholder`).
  private(set) var storeUnreadable = false
  /// What the store holds has been looked at: until then an empty Today is not "not read yet".
  private(set) var storeChecked = false

  /// Shows what the store holds, then sends the launch and the source's signals. Idempotent.
  /// The work runs in a task the feed keeps, so a window's cancelled `.task` never loses it.
  func start() {
    guard starting == nil else { return }
    guard let environment else {
      state = .unavailable
      return
    }
    consumer = Task {
      for await event in environment.coordinator.events { await apply(event) }
    }
    observeDayChanges()
    starting = Task {
      await showStored(environment.store)
      await environment.coordinator.handle(.launch)
      await environment.coordinator.run(environment.source)
    }
  }

  /// ⌘R, and a switch back to this source, which ends a pause. Live first tells the
  /// coordinator what OmniFocus' state is now, a resync of the held state.
  func refresh() {
    refresh(approving: nil)
  }

  /// Remove N lines: approves exactly the held set, then imports as ⌘R in the same call, so
  /// that import reads the approval (S4-4e).
  func approveHeldRemoval() {
    let keys = Set(heldLineRemoval.map(\.key))
    guard !keys.isEmpty else { return }
    refresh(approving: keys)
  }

  private func refresh(approving keys: Set<LineKey>?) {
    guard let environment else { return }
    let signal = Self.stateSignal(held: omniFocusState, reading: environment.omniFocusReading?())
    send { [weak self] coordinator in
      if let keys {
        await coordinator.service.approveLineRemovals(keys)
        await self?.readApproval()
      }
      await coordinator.setPaused(false)
      if let signal { await coordinator.handle(signal) }
      await coordinator.handle(.manual)
    }
  }

  private func readApproval() async {
    approvedLineRemovals = await environment?.coordinator.service.approvedLineRemovals ?? []
  }

  /// A source not shown imports nothing and keeps tracking OmniFocus (owner, 2026-11-07).
  func pause() {
    send { await $0.setPaused(true) }
  }

  private func send(_ work: @escaping @Sendable (RefreshCoordinator) async -> Void) {
    guard let coordinator = environment?.coordinator else { return }
    let previous = control
    control = Task {
      await previous?.value
      await work(coordinator)
    }
  }

  /// What ⌘R sends before itself: a start or a quit since the held state. Never frontmost →
  /// background, which the coordinator takes as resign-active (ADR-0011's median): a running
  /// OmniFocus is sent as background, and only when the held state says not running.
  nonisolated static func stateSignal(held: OmniFocusState?, reading: OmniFocusState?)
    -> ChangeSignal?
  {
    guard let reading, let held else { return nil }
    if reading == .notRunning { return held == .notRunning ? nil : .omniFocus(.notRunning) }
    return held == .notRunning ? .omniFocus(.background) : nil
  }

  /// A store that has committed shows its data, with or without an import row; an empty
  /// store (version 0) shows nothing yet; a store that cannot be read is unavailable.
  private func showStored(_ store: any Store) async {
    defer { storeChecked = true }
    // Before the version check: failure rows do not bump it. The mapping file is read by this
    // process, so a stored mapping failure says nothing about it now.
    if case .failed(let kind) = try? await store.lastImportAttempt()?.outcome,
      kind != .mappingInvalid
    {
      lastFailure = kind
    }
    do {
      guard try await store.identityMap().version > 0 else { return }
      let workspace = try await store.workspace()
      let last = try? await store.lastCommittedImport()
      guard case .loading = state else { return }
      lastImport = last
      state = .loaded(Overview(workspace: workspace, now: clock.wall()))
    } catch {
      storeUnreadable = true
      if case .loading = state { state = .unavailable }
    }
  }

  private func apply(_ event: RefreshEvent) async {
    switch event {
    case .started:
      isImporting = true
    case .committed:
      lastFailure = nil
      await reload()
      await readApproval()
      isImporting = false
      importOutcomes += 1
    case .notCommitted(let failure):
      lastFailure = failure
      if case .loading = state { state = .unavailable }
      await readApproval()
      isImporting = false
      importOutcomes += 1
    case .omniFocusNotRunning:
      break  // The note follows `omniFocusState`.
    case .omniFocusState(let new):
      omniFocusState = new
      if new != .notRunning, lastFailure == .providerNotRunning { lastFailure = nil }
    }
  }

  /// A new calendar day, or a wake from sleep past midnight, rebuilds Today from the workspace
  /// already shown: no import and no store write (owner, 2026-11-06).
  func dayMayHaveChanged() {
    guard case .loaded(let overview) = state else { return }
    let now = clock.wall()
    guard !overview.calendar.isDate(overview.now, inSameDayAs: now) else { return }
    state = .loaded(Overview(workspace: overview.workspace, now: now))
  }

  private func observeDayChanges() {
    let centres = [
      (NotificationCenter.default, Notification.Name.NSCalendarDayChanged),
      (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
    ]
    for (centre, name) in centres {
      observers.append(
        centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.dayMayHaveChanged() }
        })
    }
  }

  /// The import is read on its own: a store that cannot read it loses only the freshness text.
  /// A failed read keeps what is shown, and with nothing shown Today is unavailable.
  private func reload() async {
    guard let store = environment?.store else { return }
    lastImport = try? await store.lastCommittedImport()
    do {
      state = .loaded(Overview(workspace: try await store.workspace(), now: clock.wall()))
    } catch {
      if case .loading = state { state = .unavailable }
    }
  }
}
