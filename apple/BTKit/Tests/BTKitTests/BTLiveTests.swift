import Foundation
import Testing
@testable import BTKit

@MainActor
struct BTLiveTests {
    static let thursday = BTScreenTests.thursday

    @Test func turnsBecomeMessagesWithStreamingReplyLast() {
        let turns = [
            ChatTurn(id: "a", ts: 10, role: "user", text: "Hi", compute: nil),
            ChatTurn(id: "b", ts: 20, role: "bt", text: "Hello", compute: "openai"),
        ]
        let messages = BTLive.messages(turns: turns, streaming: "Wor", now: Self.thursday)
        #expect(messages.map(\.role) == [.user, .bt, .bt])
        #expect(messages.map(\.text) == ["Hi", "Hello", "Wor"])
        #expect(messages[0].time == Date(timeIntervalSince1970: 10))
        #expect(messages[1].isCloud)
        #expect(!messages[2].isCloud)
        #expect(messages[2].time == Self.thursday)
    }

    @Test func serverMemoriesBecomeTaggedMemories() {
        let server = [ServerMemory(name: "lab-room", description: "The CHEM lab is in room 210", type: "user", updated: "2026-10-21T18:05:00Z")]
        let memory = BTLive.memories(server)[0]
        #expect(memory.id == "lab-room")
        #expect(memory.text == "The CHEM lab is in room 210")
        #expect(memory.tag == "USER")
        #expect(memory.createdAt == Date(timeIntervalSince1970: 1_792_605_900))
    }

    @Test func emptyStreamShowsEllipsisAndNoStreamAddsNothing() {
        #expect(BTLive.messages(turns: [], streaming: "", now: Self.thursday).map(\.text) == ["…"])
        #expect(BTLive.messages(turns: [], streaming: nil, now: Self.thursday).isEmpty)
    }

    @Test func storeIsLiveOnlyWithAValidServerAddress() {
        let chat = ChatModel(makeAPI: { _ in EmptyChatAPI() })
        let store = AppStore(clock: { Self.thursday }, chat: chat)
        #expect(!store.btIsLive)
        chat.serverAddress = "not a url"
        #expect(!store.btIsLive)
        chat.serverAddress = "https://bt.example.ts.net"
        #expect(store.btIsLive)
        #expect(!AppStore(clock: { Self.thursday }).btIsLive)
    }

    @Test(arguments: [
        (nil, "NEW"),
        (-20 * 60.0, "NOW"),
        (-3 * 3600.0, "3H"),
        (-2 * 86400.0, "TUE"),
    ] as [(Double?, String)])
    func ageLabel(offset: Double?, expected: String) {
        let date = offset.map { Self.thursday.addingTimeInterval($0) }
        #expect(BTFormat.age(date, now: Self.thursday, calendar: .bt) == expected)
    }
}

private struct EmptyChatAPI: ChatAPI {
    func sessions() async throws -> [ChatSessionSummary] { [] }
    func history(sessionID: String) async throws -> [ChatTurn] { [] }
    func memories() async throws -> [ServerMemory] { [] }
}
