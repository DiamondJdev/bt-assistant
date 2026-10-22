import SwiftUI

/// Week's edit popover: title, time, ±30 nudge, Run as Focus, Save / Start focus now / Delete.
struct CalEventPopover: View {
    @Bindable var store: AppStore
    let event: CalendarEvent

    private var cal: Calendar { store.calendar }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Edit · \(CalFormat.kindLabel(event.kind))").monoLabel(10)
                    Spacer()
                    Button { store.selectedEventID = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title").font(.inter(11)).foregroundStyle(Color.btMuted)
                    TextField("Title", text: titleBinding)
                        .textFieldStyle(.plain)
                        .font(.inter(16, .medium))
                        .frame(height: 34)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.btInk).frame(height: 1.5) }
                }
                HStack(alignment: .top, spacing: 10) {
                    field("When") {
                        Text(CalFormat.string(event.start, "EEE", cal) + " " + CalFormat.range(event.start, event.end, cal))
                            .font(.inter(13))
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .background(Color.white)
                            .overlay(Rectangle().strokeBorder(Color.btLine, lineWidth: 1))
                    }
                    field("Nudge") {
                        HStack(spacing: 4) {
                            nudge("−30", minutes: -30)
                            nudge("+30", minutes: 30)
                        }
                    }
                }
                Toggle(isOn: focusBinding) {
                    Text("Run as Focus session ").font(.inter(13))
                        + Text("· \(planLabel)").font(.inter(13)).foregroundStyle(Color.btMuted)
                }
                .toggleStyle(CalCheckboxStyle(accent: true, trailing: true))
                HStack(spacing: 8) {
                    Button("Save") { store.selectedEventID = nil }.buttonStyle(.pill(.primary))
                    Button("Start focus now") { store.startFocus(from: event) }.buttonStyle(.pill(.secondary))
                    Spacer(minLength: 0)
                    Button("Delete") { store.deleteEvent(event.id) }
                        .buttonStyle(.plain)
                        .font(.inter(13))
                        .underline()
                        .foregroundStyle(Color.btAccentDeep)
                        .frame(minHeight: 36)
                }
            }
        }
        .foregroundStyle(Color.btInk)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit event")
    }

    private var planLabel: String {
        (event.focusPlan ?? "50/10").replacingOccurrences(of: "/", with: " / ")
    }

    private var titleBinding: Binding<String> {
        Binding(get: { store.event(event.id)?.title ?? event.title }, set: { store.calSetTitle(event.id, $0) })
    }

    private var focusBinding: Binding<Bool> {
        Binding(get: { store.event(event.id)?.runAsFocus ?? false }, set: { store.calSetRunAsFocus(event.id, $0) })
    }

    private func field<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.inter(11)).foregroundStyle(Color.btMuted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nudge(_ label: String, minutes: Int) -> some View {
        Button { store.calNudge(event.id, minutes: minutes) } label: {
            Text(label).font(.inter(12))
                .frame(maxWidth: .infinity, minHeight: 32)
                .overlay(Rectangle().strokeBorder(Color.btInk, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(minutes < 0 ? "30 minutes earlier" : "30 minutes later")
    }
}

/// Square checkbox drawn in the Sand Grid style (ImageRenderer-safe, unlike the AppKit one).
struct CalCheckboxStyle: ToggleStyle {
    var accent = false
    var trailing = false
    var size: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                if trailing {
                    configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                    box(configuration.isOn)
                } else {
                    box(configuration.isOn)
                    configuration.label
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }

    private func box(_ on: Bool) -> some View {
        let tint = accent ? Color.btAccent : .btInk
        return Rectangle()
            .fill(on ? tint : .clear)
            .overlay(Rectangle().strokeBorder(on ? tint : .btInk, lineWidth: 1.5))
            .overlay(on ? Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(accent ? Color.btOnAccent : .btInkOnDark) : nil)
            .frame(width: size, height: size)
    }
}
