import SwiftUI

struct CalWeekToolbar: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 16) {
            Text(CalWeekLayout.weekTitle(store.calendarDate, calendar: store.calendar))
                .interStyle(36, .medium, tracking: -0.045)
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                navigation("chevron.left", label: "Previous week", step: -1)
                Button("Today") {
                    store.selectedEventID = nil
                    store.calGoToday()
                    store.calendarScreen.weekTodayRequest += 1
                }.buttonStyle(.pill(.secondary))
                navigation("chevron.right", label: "Next week", step: 1)
            }
            CalModePicker(mode: $store.calendarMode)
            Button("+ New") { store.calNewEvent() }.buttonStyle(.pill(.cta))
        }
        .foregroundStyle(Color.btInk)
        .padding(.horizontal, 32).padding(.vertical, 20)
    }

    private func navigation(_ symbol: String, label: String, step: Int) -> some View {
        Button { store.calStep(step) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                .frame(width: 36, height: 36).contentShape(Circle())
                .overlay(Circle().strokeBorder(Color.btInk, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
