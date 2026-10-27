import CryptoKit
import Foundation

enum RoadmapEditing {
    static func revision(_ stages: [RoadmapStage]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try encoder.encode(stages)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppStore {
    func saveRoadmap(projectID: String, stages: [RoadmapStage], expectedRevision: String) throws {
        guard let projectIndex = projects.firstIndex(where: { $0.id == projectID }) else {
            throw ToolError.badArguments("No tracked project with that project_id.")
        }
        let previous = projects[projectIndex].stages
        guard try RoadmapEditing.revision(previous) == expectedRevision else {
            throw ToolError.failed("The roadmap changed while this edit was open. Read it again and review the new changes before saving.")
        }
        guard (1...12).contains(stages.count) else {
            throw ToolError.badArguments("Keep between 1 and 12 stages.")
        }
        var identifiers = Set<String>()
        var hasCurrentStage = false
        let updated = try stages.enumerated().map { index, original in
            var stage = original
            stage.name = stage.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let old = previous.first { $0.id == stage.id }
            guard !stage.id.isEmpty, identifiers.insert(stage.id).inserted,
                  !stage.name.isEmpty, stage.name.count <= 160, stage.tasks.count <= 12,
                  !stage.tasks.isEmpty || old?.tasks.isEmpty == true else {
                throw ToolError.badArguments("Each stage needs a unique ID, a name up to 160 characters and 1–12 tasks. Existing empty stages may stay empty.")
            }
            stage.tasks = try stage.tasks.map { original in
                var task = original
                task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !task.id.isEmpty, identifiers.insert(task.id).inserted,
                      !task.title.isEmpty, task.title.count <= 300 else {
                    throw ToolError.badArguments("Each task needs a unique ID and a title up to 300 characters.")
                }
                return task
            }
            stage.index = index + 1
            let done = stage.tasks.isEmpty ? old?.status == .done : stage.tasks.allSatisfy { $0.status == .done }
            if !stage.tasks.isEmpty {
                stage.progress = Double(stage.tasks.filter { $0.status == .done }.count) / Double(stage.tasks.count)
            }
            if done {
                stage.status = .done
                stage.progress = 1
                stage.completedDate = old?.completedDate ?? now
            } else {
                stage.status = hasCurrentStage ? (index == stages.count - 1 ? .final : .next) : .current
                stage.completedDate = nil
                hasCurrentStage = true
            }
            return stage
        }
        projects[projectIndex].stages = updated
    }

    @discardableResult
    func editRoadmap(projectID: String) async -> Bool {
        guard let project = project(projectID), !project.stages.isEmpty else { return false }
        route = .bt
        guard let chat, btIsLive, !chat.isSending,
              chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        chat.startNewConversation()
        chat.draft = """
        Help me edit the roadmap or update progress for \(project.name).
        Project ID: \(project.id)
        First use roadmap_get to read the current stages, task statuses, IDs and revision. Ask what I want to change, one focused question at a time. Never infer completed work. Keep existing IDs for items that remain, omit IDs for new items, and keep every unchanged stage and task in roadmap_update. Omitted items are removed, so explain any removals before requesting approval. Use the revision from roadmap_get as expected_revision. Progress and the current stage are calculated from task statuses. After a conflict, read the roadmap again and review the revised proposal with me. Do not claim changes were saved until roadmap_update succeeds.
        """
        await chat.send()
        return chat.errorMessage == nil
    }
}
