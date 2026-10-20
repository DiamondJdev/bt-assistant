import Testing
@testable import BTKit

struct ContextSnapshotTests {
    @Test func keepsOrderAndSkipsNilAndEmpty() {
        #expect(contextSnapshot(["A", nil, "", "B"]) == "A\nB")
    }

    @Test func allNilOrEmptyGivesNil() {
        #expect(contextSnapshot([nil, "", nil]) == nil)
        #expect(contextSnapshot([]) == nil)
    }

    @Test func oversizedFragmentIsSkippedAndALaterShortOneFits() {
        let long = String(repeating: "x", count: 8)
        #expect(contextSnapshot(["abc", long, "de"], budget: 6) == "abc\nde")
        #expect(contextSnapshot([long], budget: 6) == nil)
    }

    @Test func newlinesCountTowardTheBudget() {
        #expect(contextSnapshot(["abc", "de"], budget: 5) == "abc")
        #expect(contextSnapshot(["abc", "de"], budget: 6) == "abc\nde")
    }
}
