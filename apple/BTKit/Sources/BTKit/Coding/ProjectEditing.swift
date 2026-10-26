import Foundation

extension AppStore {
    static let maxProjectNameLength = 80
    static let weeklyGoalRange = 0.5...80.0

    /// Saves the details set in the project sheet. Throws on a blank name or a goal outside 0.5–80 hours.
    func updateProject(_ id: String, name: String, path: String, weeklyGoalHours: Double?, bookmark: Data? = nil) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else {
            throw ToolError.badArguments("No tracked project with that ID.")
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= Self.maxProjectNameLength else {
            throw ToolError.badArguments("Give the project a name up to \(Self.maxProjectNameLength) characters.")
        }
        if let weeklyGoalHours, !Self.weeklyGoalRange.contains(weeklyGoalHours) {
            throw ToolError.badArguments("Set a weekly goal from 0.5 to 80 hours, or leave it blank.")
        }
        var project = projects[index]
        project.name = name
        project.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        project.weeklyGoalHours = weeklyGoalHours
        if let bookmark { project.bookmark = bookmark }
        projects[index] = project
    }

    /// Removes a project with its roadmap and goal. Its coding history stays on disk, hidden until
    /// the repo is tracked again.
    func removeProject(_ id: String) {
        projects.removeAll { $0.id == id }
        hiddenProjectIDs.insert(id)
        code.accepted[id] = nil
        if selectedProjectID == id { selectedProjectID = nil }
        if focus.projectID == id { focus.projectID = nil }
    }
}

extension AppStore {
    /// Bookmark for a folder from the file importer. The app keeps read access to it across launches.
    static func repoBookmark(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        return try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        #else
        return try? url.bookmarkData()
        #endif
    }
}
