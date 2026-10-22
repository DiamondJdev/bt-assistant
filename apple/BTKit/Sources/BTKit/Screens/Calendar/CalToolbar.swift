import SwiftUI

/// Shared toolbar: title, meta, prev/Today/next, Day/Week/Month, "+ New event".
struct CalToolbar: View {
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 20) {
            Text(title).interStyle(40, .medium, tracking: -0.045).lineLimit(1)
            if store.calendarMode == .month {
                CalMonthLayerPills(state: store.calendarScreen)
            } else {
                Text(meta).monoLabel().lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                roundButton("‹", label: "Previous \(store.calendarMode.rawValue)") { store.calStep(-1) }
                Button("Today") { store.calGoToday() }.buttonStyle(.pill(.secondary))
                roundButton("›", label: "Next \(store.calendarMode.rawValue)") { store.calStep(1) }
            }
            CalModePicker(mode: $store.calendarMode)
            Button("+ New event") { store.calNewEvent() }.buttonStyle(.pill(.cta))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var cal: Calendar { store.calendar }

    private var title: String {
        switch store.calendarMode {
        case .week:
            let days = CalDates.weekDays(store.calendarDate, cal)
            return CalFormat.span(days[0], days[6], cal)
        case .day:
            return CalFormat.string(store.calendarDate, "EEEE d", cal)
        case .month:
            let sameYear = cal.isDate(store.calendarDate, equalTo: store.now, toGranularity: .year)
            return CalFormat.string(store.calendarDate, sameYear ? "MMMM" : "MMMM yyyy", cal)
        }
    }

    private var meta: String {
        switch store.calendarMode {
        case .week:
            let days = CalDates.weekDays(store.calendarDate, cal)
            let end = cal.date(byAdding: .day, value: 7, to: days[0])!
            let week = store.events.filter { $0.start >= days[0] && $0.start < end && $0.kind != .deadline }
            let n = cal.component(.weekOfYear, from: days[0])
            guard !week.isEmpty else { return "Week \(n) · nothing booked" }
            let booked = week.filter { $0.kind != .work }.reduce(0) { $0 + $1.duration } / 3600
            let study = week.filter { $0.kind != .work && $0.kind != .classSession }.reduce(0) { $0 + $1.duration } / 3600
            return "Week \(n) · \(Int(booked.rounded()))h booked · \(Int(study.rounded()))h study"
        case .day:
            let day = store.events(on: store.calendarDate)
            let due = day.filter { $0.kind == .deadline }.count
            return CalFormat.string(store.calendarDate, "MMMM", cal) + " · \(day.count - due) events · \(due) due"
        case .month:
            return ""
        }
    }

    private func roundButton(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.inter(16))
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Color.btInk, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Day / Week / Month segmented pill.
struct CalModePicker: View {
    @Binding var mode: CalendarMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CalendarMode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.rawValue.capitalized)
                        .font(.inter(13))
                        .foregroundStyle(mode == m ? Color.btInkOnDark : .btInk)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(mode == m ? Color.btInk : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == m ? .isSelected : [])
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.btInk, lineWidth: 1))
    }
}

/// Month layer pills (Study / Due / Class / Work).
struct CalMonthLayerPills: View {
    @Bindable var state: CalendarScreenState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CalMonthLayer.allCases, id: \.self) { layer in
                let on = state.monthLayers.contains(layer)
                Button(layer.name) {
                    if on { state.monthLayers.remove(layer) } else { state.monthLayers.insert(layer) }
                }
                .buttonStyle(.pill(on ? .primary : .secondary, size: .small))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
