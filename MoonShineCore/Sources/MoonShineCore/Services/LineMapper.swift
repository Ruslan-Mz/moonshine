/// What line mapping needs to know about a project; names are already resolved from ids.
public struct ProjectContext: Hashable, Sendable {
  public let name: String
  /// Non-meta tag names only.
  public let tagNames: [String]
  public let topLevelFolder: String?

  public init(name: String, tagNames: [String], topLevelFolder: String?) {
    self.name = name
    self.tagNames = tagNames
    self.topLevelFolder = topLevelFolder
  }
}

/// Assigns tasks and projects to lines (snapshot-contract §Mapping). First match wins:
/// task tag → project tag → project name → top-level folder → Life ops.
public struct LineMapper: Sendable {
  private var byTag: [String: LineID] = [:]
  private var byProject: [String: LineID] = [:]
  private var byFolder: [String: LineID] = [:]
  public private(set) var issues: [ImportIssue] = []

  public init(lines: [Line]) {
    var owners: [String: LineKey] = [:]
    for line in lines {
      let rules = line.taskRules
      for tag in rules.tags { claim(tag, as: "tag", line, in: \.byTag, owners: &owners) }
      for name in rules.projects {
        claim(name, as: "project", line, in: \.byProject, owners: &owners)
      }
      for name in rules.folders { claim(name, as: "folder", line, in: \.byFolder, owners: &owners) }
    }
  }

  private mutating func claim(
    _ name: String, as kind: String, _ line: Line,
    in index: WritableKeyPath<LineMapper, [String: LineID]>, owners: inout [String: LineKey]
  ) {
    let rule = "\(kind) \(name)"
    if let owner = owners[rule] {
      if owner != line.key {
        issues.append(.ruleClaimedTwice(rule: rule, kept: owner, ignored: line.key))
      }
      return
    }
    owners[rule] = line.key
    self[keyPath: index][name] = line.id
  }

  public func assign(taskTags: [String], project: ProjectContext?) -> LineAssignment {
    if let id = taskTags.lazy.compactMap({ byTag[$0] }).first {
      return .line(id)
    }
    guard let project else { return .lifeOps }
    return assign(project: project)
  }

  public func assign(project: ProjectContext) -> LineAssignment {
    if let id = project.tagNames.lazy.compactMap({ byTag[$0] }).first
      ?? byProject[project.name]
      ?? project.topLevelFolder.flatMap({ byFolder[$0] })
    {
      return .line(id)
    }
    return .lifeOps
  }
}
