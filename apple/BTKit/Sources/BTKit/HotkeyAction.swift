/// What the global hotkey does: hide BT when it's in front with its window
/// showing, otherwise bring BT up on Calendar.
public enum HotkeyAction: Equatable {
    case hide
    case showCalendar

    public static func resolve(appIsActive: Bool, mainWindowVisible: Bool) -> HotkeyAction {
        appIsActive && mainWindowVisible ? .hide : .showCalendar
    }
}
