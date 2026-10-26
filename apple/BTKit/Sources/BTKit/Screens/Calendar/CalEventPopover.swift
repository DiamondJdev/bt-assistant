import SwiftUI

struct CalEventEditor: View {
    @Bindable var store: AppStore
    @State var draft: CalEventDraft
    @State private var saveError: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(draft.isNew ? "New event" : draft.isEditable ? "Edit event" : "Event details")
                    .interStyle(28, .medium, tracking: -0.035)
                Spacer()
                Button { store.calCancelEditor() } label: {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .keyboardShortcut(.cancelAction)
            }
            .padding(BTMetrics.cellPadding)
            .dashedEdges(right: false, bottom: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Title").monoLabel()
                        TextField("Event title", text: $draft.event.title)
                            .textFieldStyle(.plain)
                            .font(.inter(22, .medium))
                            .padding(12)
                            .background(Color.btPaper)
                            .overlay(Rectangle().strokeBorder(Color.btLine, lineWidth: 1))
                            .accessibilityLabel("Title")
                            .disabled(!draft.isEditable)
                        Text(CalFormat.sourceLabel(draft.event))
                            .font(.mono(11))
                            .foregroundStyle(Color.btMuted)
                        if let location = draft.event.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.inter(13))
                                .foregroundStyle(Color.btMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Time window").monoLabel()
                        DatePicker("Date", selection: startBinding, displayedComponents: .date)
                        DatePicker("Starts", selection: startBinding, displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: $draft.event.end, displayedComponents: [.date, .hourAndMinute])
                    }
                    .datePickerStyle(.field)
                    .disabled(!draft.isEditable)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Duration").monoLabel()
                            Spacer()
                            Text(CalFormat.hours(draft.event.duration / 3600)).font(.mono(13))
                        }
                        if draft.isEditable {
                            HStack(spacing: 8) {
                                ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                                    Button("\(minutes)m") { draft.setDuration(minutes: minutes) }
                                        .buttonStyle(.pill(.secondary, size: .small))
                                        .accessibilityLabel("Set duration to \(minutes) minutes")
                                }
                            }
                        }
                    }
                    if draft.isEditable {
                        Toggle("Run as Focus session", isOn: $draft.event.runAsFocus)
                            .toggleStyle(CalCheckboxStyle())
                            .onChange(of: draft.event.runAsFocus) { _, enabled in
                                if enabled, draft.event.focusPlan == nil { draft.event.focusPlan = "50/10" }
                            }
                    }
                    if !draft.isValid {
                        Text("Enter a title and an end time after the start.")
                            .font(.inter(13)).foregroundStyle(Color.btAccentDeep)
                    }
                    if let saveError {
                        Text(saveError).font(.inter(13)).foregroundStyle(Color.btAccentDeep)
                            .accessibilityLabel("Could not save. \(saveError)")
                    }
                }
                .font(.inter(14))
                .padding(BTMetrics.cellPadding)
            }
            VStack(alignment: .leading, spacing: 12) {
                if draft.isEditable, draft.event.runAsFocus {
                    Button("Save & start focus") { save(startFocus: true) }
                        .buttonStyle(.pill(.secondary))
                        .disabled(!draft.isValid)
                }
                HStack(spacing: 10) {
                    if !draft.isNew, draft.isEditable {
                        Button("Delete", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.plain)
                            .font(.inter(13, .medium))
                            .foregroundStyle(Color.btAccentText)
                    }
                    Spacer()
                    Button(draft.isEditable ? "Cancel" : "Done") { store.calCancelEditor() }
                        .buttonStyle(.pill(.secondary))
                    if draft.isEditable {
                        Button("Save") { save() }
                            .buttonStyle(.pill(.primary))
                            .keyboardShortcut(.defaultAction)
                            .disabled(!draft.isValid)
                    }
                }
            }
            .padding(BTMetrics.cellPadding)
            .dashedEdges(right: false, bottom: false, top: true)
        }
        .frame(width: 540, height: 620)
        .background(Color.btGround)
        .foregroundStyle(Color.btInk)
        .tint(Color.btAccent)
        .environment(\.colorScheme, .light)
        .environment(\.calendar, store.calendar)
        .environment(\.timeZone, store.calendar.timeZone)
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete event", role: .destructive) {
                if store.deleteEvent(draft.event.id) != nil {
                    store.calCancelEditor()
                } else {
                    saveError = store.calendarError ?? "This event is no longer available."
                }
            }
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { draft.event.start }, set: { draft.moveStart(to: $0) })
    }

    private func save(startFocus: Bool = false) {
        if !store.calSaveEditor(draft, startFocus: startFocus) {
            saveError = store.calendarError ?? "This event is no longer available. Close and reopen it."
        }
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
