import SwiftUI

struct CalWeekColumns {
    static let gutter: CGFloat = 44
    static let gap: CGFloat = 6
    let width: CGFloat
    var columnWidth: CGFloat { max(0, (width - Self.gutter - Self.gap * 7) / 7) }
    func x(_ day: Int) -> CGFloat { Self.gutter + Self.gap + CGFloat(day) * (columnWidth + Self.gap) }
}

struct CalWeekGrid: View {
    @Bindable var store: AppStore
    @State private var showsUpcoming = false
    @State private var scrollTarget = CalWeekLayout.initialScroll
    @State private var scrollRequest = 0

    private var calendar: Calendar { store.calendar }
    private var days: [Date] { CalWeekLayout.days(containing: store.calendarDate, calendar: calendar) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                header(now: context.date)
                allDayStrip
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            grid(width: geometry.size.width, now: context.date)
                                .overlay(alignment: .topLeading) {
                                    VStack(spacing: 0) {
                                        Color.clear.frame(height: scrollTarget)
                                        Color.clear.frame(height: 1).id("week-scroll-target")
                                    }.allowsHitTesting(false).accessibilityHidden(true)
                                }
                        }
                        .task(id: scrollRequest) {
                            await Task.yield()
                            proxy.scrollTo("week-scroll-target", anchor: .top)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            CalWeekCard(store: store, now: context.date, showsUpcoming: $showsUpcoming) { event in
                                select(event)
                                scroll(to: max(0, CalWeekLayout.y(event.start, calendar: calendar) - 120))
                            }
                            .frame(width: min(showsUpcoming || store.selectedEventID != nil ? 360 : 320,
                                              max(0, geometry.size.width - 64)))
                            .frame(maxHeight: max(0, geometry.size.height - 48), alignment: .bottom)
                            .padding(.trailing, 32).padding(.bottom, 24)
                        }
                    }
                }
            }
            .onChange(of: days[0]) { _, _ in
                store.selectedEventID = nil
                showsUpcoming = false
                scroll(to: CalWeekLayout.initialScroll)
            }
            .onChange(of: store.calendarScreen.weekTodayRequest) { _, _ in
                showsUpcoming = false
                scroll(to: max(0, CalWeekLayout.y(context.date, calendar: calendar) - 200))
            }
        }
    }

    private func scroll(to position: CGFloat) {
        scrollTarget = min(CalWeekLayout.gridHeight - 1, position)
        scrollRequest += 1
    }

    private func select(_ event: CalendarEvent) {
        store.selectedEventID = event.id
        showsUpcoming = false
    }

    @ViewBuilder private var allDayStrip: some View {
        let eventsByDay = days.map { store.allDayEvents(on: $0) }
        let rowCount = eventsByDay.map(\.count).max() ?? 0
        if rowCount > 0 {
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 0) {
                    Text("ALL DAY").font(.mono(10)).foregroundStyle(Color.btMuted)
                        .frame(width: CalWeekLayout.gutter, alignment: .center).padding(.top, 14)
                    ScrollView(.vertical) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(eventsByDay[index]) { event in
                                        Button { select(event) } label: {
                                            Text(event.title).font(.inter(11, .medium)).lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(6).background(Color.btPaper)
                                                .overlay(Rectangle().strokeBorder(store.selectedEventID == event.id ? Color.btAccent : Color.btLine))
                                        }
                                        .buttonStyle(.plain).help(event.title)
                                        .accessibilityLabel("\(event.title), all day, \(CalFormat.string(days[index], "EEEE, MMM d", calendar))")
                                    }
                                }
                                .padding(.horizontal, 4).padding(.vertical, 8)
                                .frame(width: max(0, (geometry.size.width - CalWeekLayout.gutter) / 7), alignment: .topLeading)
                            }
                        }
                    }
                }
            }
            .frame(height: min(160, CGFloat(rowCount) * 30 + 16))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.btLine).frame(height: 1) }
        }
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CalWeekLayout.gutter)
            ForEach(days, id: \.self) { day in
                let today = calendar.isDate(day, inSameDayAs: now)
                VStack(alignment: .leading, spacing: 8) {
                    Text(CalFormat.string(day, "EEE", calendar).uppercased())
                        .font(.mono(11)).tracking(0.88)
                        .foregroundStyle(today ? Color.btAccentText : .btMuted)
                    HStack(spacing: 4) {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.inter(18, .medium))
                            .foregroundStyle(today ? Color.btOnAccent : .btInk)
                            .frame(width: 38, height: 30)
                            .background(today ? Color.btAccent : .clear, in: Capsule())
                        Spacer(minLength: 0)
                        Text("\(CalWeekLayout.events(on: day, in: store.events, calendar: calendar).count)")
                            .font(.mono(10)).foregroundStyle(Color.btMuted)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.btLine).frame(height: 1) }
    }

    private func grid(width: CGFloat, now: Date) -> some View {
        let columnWidth = max(0, (width - CalWeekLayout.gutter) / 7)
        let nowY = CalWeekLayout.y(now, calendar: calendar)
        let showsNow = nowY >= 0 && nowY < CalWeekLayout.gridHeight && days.contains { calendar.isDate($0, inSameDayAs: now) }
        return ZStack(alignment: .topLeading) {
            Color.btGround.onTapGesture { store.selectedEventID = nil; showsUpcoming = false }
            ForEach(0...24, id: \.self) { index in
                Rectangle().fill(Color.btRule).frame(width: max(0, width - CalWeekLayout.gutter), height: 1)
                    .offset(x: CalWeekLayout.gutter, y: CGFloat(index) * 100)
                    .allowsHitTesting(false)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let today = calendar.isDate(day, inSameDayAs: now)
                ZStack(alignment: .topLeading) {
                    if today { Color.btPaper.opacity(0.6).allowsHitTesting(false) }
                    Rectangle().fill(Color.btRule).frame(width: 1).allowsHitTesting(false)
                    ForEach(CalWeekLayout.cascade(CalWeekLayout.events(on: day, in: store.events, calendar: calendar)), id: \.event.id) { placed in
                        if let frame = CalWeekLayout.frame(placed.event, on: day, calendar: calendar) {
                            block(placed, width: columnWidth, frame: frame)
                        }
                    }
                    if today && showsNow {
                        Rectangle().fill(Color.btAccent).frame(height: 2).offset(y: nowY).zIndex(40)
                            .allowsHitTesting(false)
                        Circle().fill(Color.btAccent).frame(width: 12, height: 12).offset(x: -6, y: nowY - 5).zIndex(40)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: columnWidth, height: CalWeekLayout.gridHeight)
                .offset(x: CalWeekLayout.gutter + CGFloat(index) * columnWidth)
            }
            ForEach(0...23, id: \.self) { hour in
                Text(hour == 12 ? "Noon" : "\(hour == 0 ? 12 : hour > 12 ? hour - 12 : hour) \(hour < 12 ? "AM" : "PM")")
                    .font(.mono(11)).foregroundStyle(Color.btMuted)
                    .frame(width: CalWeekLayout.gutter - 12, height: 20, alignment: .trailing)
                    .offset(y: max(0, CGFloat(hour) * CalWeekLayout.hourHeight - 10))
                    .allowsHitTesting(false)
            }
            if showsNow {
                Text(CalFormat.string(now, "h:mm", calendar)).font(.mono(11, .medium))
                    .foregroundStyle(Color.btOnAccent)
                    .padding(.horizontal, 5).frame(height: 24).background(Color.btAccent)
                    .offset(x: 6, y: nowY - 11).allowsHitTesting(false)
            }
        }
        .frame(width: width, height: CalWeekLayout.gridHeight).clipped()
    }

    private func block(_ placed: CalWeekLayout.Placed, width: CGFloat, frame: (y: CGFloat, height: CGFloat)) -> some View {
        let indent = min(CGFloat(placed.indent) * 16, max(0, width - 28))
        let laneWidth = (width - indent) / CGFloat(placed.cols)
        let selected = store.selectedEventID == placed.event.id
        return Button { select(placed.event) } label: {
            CalWeekEventBlock(event: placed.event, height: frame.height, shared: placed.cols > 1,
                              layered: placed.indent > 0 || placed.col > 0, selected: selected, calendar: calendar)
                .frame(width: max(0, laneWidth - 8), height: frame.height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: indent + CGFloat(placed.col) * laneWidth + 4, y: frame.y)
        .zIndex(selected ? 1000 : Double(placed.z))
        .accessibilityLabel("\(placed.event.title), \(CalWeekLayout.range(placed.event, calendar: calendar)), \(placed.event.location ?? "No location")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CalWeekEventBlock: View {
    let event: CalendarEvent
    let height: CGFloat
    let shared: Bool
    let layered: Bool
    let selected: Bool
    let calendar: Calendar

    private var kind: CalWeekKind { CalWeekKind.classify(event) }
    private var fill: Color {
        switch kind {
        case .classSession: Color(hex: 0xDCCFBF)
        case .meeting: Color(hex: 0xFBF7F2)
        case .studyBlock: Color(hex: 0xEFE6DA)
        case .work, .personal: Color(hex: 0xE3D5C3)
        }
    }
    private var border: Color {
        switch kind {
        case .classSession: Color(hex: 0xA89888)
        case .meeting: .btInk
        case .studyBlock: Color(hex: 0x8C7E70)
        case .work, .personal: .btLine
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.title).font(.inter(13, .semibold)).foregroundStyle(Color.btInk)
                .lineLimit(height >= 100 ? 2 : 1)
            if height >= 44 {
                Text(CalWeekLayout.range(event, calendar: calendar))
                    .font(.mono(11)).foregroundStyle(Color(hex: 0x5A4C3E)).lineLimit(1)
            }
            if height >= 72 && !shared, let location = event.location, !location.isEmpty {
                Text(location).font(.inter(12)).foregroundStyle(Color(hex: 0x5A4C3E)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9).padding(.vertical, height >= 44 ? 6 : 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill).clipped()
        .overlay(Rectangle().strokeBorder(selected ? Color.btInk : border,
                                         style: StrokeStyle(lineWidth: selected || kind == .studyBlock ? 1.5 : 1,
                                                            dash: kind == .studyBlock && !selected ? [4, 3] : [])))
        .background { if layered { Rectangle().stroke(Color.btGround, lineWidth: 4) } }
        .shadow(color: .btInk.opacity(layered ? 0.12 : 0), radius: 6, y: 2)
        .overlay { if selected { Rectangle().stroke(Color.btAccent, lineWidth: 3).padding(-3) } }
    }
}
