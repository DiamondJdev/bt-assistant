import Testing
@testable import BTKit

struct HotkeyActionTests {
    @Test func hidesOnlyWhenActiveWithAVisibleWindow() {
        #expect(HotkeyAction.resolve(appIsActive: true, mainWindowVisible: true) == .hide)
        #expect(HotkeyAction.resolve(appIsActive: true, mainWindowVisible: false) == .showCalendar)
        #expect(HotkeyAction.resolve(appIsActive: false, mainWindowVisible: true) == .showCalendar)
        #expect(HotkeyAction.resolve(appIsActive: false, mainWindowVisible: false) == .showCalendar)
    }
}
