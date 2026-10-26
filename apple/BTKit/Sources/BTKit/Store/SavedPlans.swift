import Foundation
import os

/// The focus task and goals, and every project with its goal, roadmap and path. Coding and focus
/// time aren't here: heartbeats and focus sessions are in SwiftData.
/// ponytail: one JSON value in UserDefaults; move to SwiftData if roadmaps grow past a few KB.
struct SavedPlans: Codable, Equatable {
    struct Focus: Codable, Equatable {
        var taskTitle: String
        var projectID: String?
        var goals: [SessionGoal]
    }

    struct ProjectPlan: Codable, Equatable {
        var id: String
        var name: String
        var path: String
        var stack: String
        var branch: String?
        var weeklyGoalHours: Double?
        var stages: [RoadmapStage]
        var bookmark: Data?
    }

    static let key = "store.plans"
    private static let logger = Logger(subsystem: "BTKit", category: "SavedPlans")

    var focus: Focus
    var projects: [ProjectPlan]
    /// Optional so plans saved before projects could be removed still decode.
    var hiddenProjectIDs: [String]?

    /// Keeps every project, so one stays listed however long ago it was last coded on.
    init(focus: ActiveFocusSession, projects: [Project], hiddenProjectIDs: Set<String> = []) {
        self.focus = Focus(taskTitle: focus.taskTitle, projectID: focus.projectID, goals: focus.goals)
        self.projects = projects.map {
            ProjectPlan(id: $0.id, name: $0.name, path: $0.path, stack: $0.stack, branch: $0.branch,
                        weeklyGoalHours: $0.weeklyGoalHours, stages: $0.stages, bookmark: $0.bookmark)
        }
        self.hiddenProjectIDs = hiddenProjectIDs.isEmpty ? nil : hiddenProjectIDs.sorted()
    }

    var savedProjects: [Project] {
        projects.map { Project(id: $0.id, name: $0.name, path: $0.path, stack: $0.stack, branch: $0.branch,
                               weeklyGoalHours: $0.weeklyGoalHours, stages: $0.stages, bookmark: $0.bookmark) }
    }

    static func load(from defaults: UserDefaults) -> SavedPlans? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(SavedPlans.self, from: data)
        } catch {
            logger.error("Could not read saved plans: \(error.localizedDescription)")
            return nil
        }
    }

    func save(to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(self), forKey: Self.key)
        } catch {
            Self.logger.error("Could not save plans: \(error.localizedDescription)")
        }
    }
}
