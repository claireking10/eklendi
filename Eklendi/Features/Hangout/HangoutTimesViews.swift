import SwiftUI

// MARK: - Screen 08: swipe on times (KAL-26)

@MainActor
struct HFSwipeTimesView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    /// Slots I swiped before (on this device), so a suggested time only asks for the new card.
    @State private var priorVoted: Set<String>
    @State private var votes: [String: Vote] = [:]
    @State private var finished: Bool = false
    @State private var submitting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var daySlot: TimeSlot? = nil

    init(store: HFHangoutStore, uid: String, hangoutId: String) {
        self.store = store
        self.uid = uid
        self.hangoutId = hangoutId
        _priorVoted = State(initialValue: HFLocalStore.votedSlotIds(hangoutId: hangoutId, uid: uid))
    }

    private var items: [TimeSlot] {
        let all: [TimeSlot] = store.votableSlots
        let fresh: [TimeSlot] = all.filter { !priorVoted.contains($0.id) }
        return fresh.isEmpty ? all : fresh
    }

    private var eyebrow: String {
        let h: Hangout? = store.hangout
        return "\(store.displayName(uid: uid)) · \(HFRouting.stepLabel(.votingTimes, mode: h?.mode ?? .timeAndActivity))"
    }

    private var subtitle: String? {
        let msg: String = store.hangout?.statusMessage ?? ""
        return msg.isEmpty ? nil : msg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HFHeader(eyebrow: eyebrow, title: finished ? "Times are in." : "Let’s find a time.", subtitle: finished ? nil : subtitle)
            if finished {
                doneView
            } else if items.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().tint(EKColor.teal)
                    Spacer()
                }
                Spacer()
            } else {
                let total: Int = items.count
                let answered: Int = min(votes.count, total)
                EKProgressBar(progress: Double(answered) / Double(max(total, 1)),
                              label: "\(min(answered + 1, total)) of \(total)")
                SwipeCardStack(items: items, onVote: { slot, vote in
                    votes[slot.id] = vote
                }, onFinished: {
                    finished = true
                    submit()
                }) { slot in
                    slotCard(slot)
                }
                .frame(maxHeight: .infinity)
                Text("Swipe right if it works, left if it doesn’t, or down if you’d go but would rather not.")
                    .font(EKFont.inter(13))
                    .foregroundStyle(EKColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, EKSpacing.screen)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .fullScreenCover(item: $daySlot) { slot in
            HFDayAvailabilityView(store: store, uid: uid, hangoutId: hangoutId, referenceSlot: slot)
                .environment(env)
        }
    }

    // MARK: Card

    private func slotCard(_ slot: TimeSlot) -> some View {
        let missingNames: [String] = slot.missingMemberIds.map { store.memberName($0) }
        let everyone: [String] = store.inGroup
            .filter { !slot.missingMemberIds.contains($0.id) }
            .map { $0.name }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(slot.label.isEmpty ? (slot.source == .suggested ? "Suggested" : "Option") : slot.label)
                    .font(EKFont.inter(16, .bold))
                    .foregroundStyle(EKColor.textPrimary)
                Spacer()
                Pill(HFFormat.durationLabel(slot.start, slot.end))
            }
            Spacer(minLength: 12)
            Text(HFFormat.monthDayOrdinal(slot.start))
                .font(EKFont.inter(20, .bold))
                .foregroundStyle(EKColor.teal)
            Text(HFFormat.weekdayUpper(slot.start))
                .font(EKFont.display)
                .foregroundStyle(EKColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(HFFormat.timeRange(slot.start, slot.end))
                .font(EKFont.inter(20, .bold))
                .foregroundStyle(EKColor.textPrimary)
            if !slot.reason.isEmpty {
                Text(slot.reason)
                    .font(EKFont.inter(13))
                    .foregroundStyle(EKColor.muted)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                daySlot = slot
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text("View availability")
                }
                .font(EKFont.inter(14, .bold))
                .foregroundStyle(EKColor.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Capsule().fill(EKColor.raised))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .accessibilityIdentifier("viewAvailabilityButton")
            Spacer(minLength: 12)
            if missingNames.isEmpty {
                HStack {
                    Text("Everyone’s free")
                        .font(EKFont.inter(16, .bold))
                        .foregroundStyle(EKColor.onTeal)
                    Spacer()
                    AvatarStack(names: everyone, size: 28, ringColor: EKColor.teal, maxVisible: 4)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(EKColor.teal))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.xmark")
                    Text("Without \(HFFormat.joinNames(missingNames))")
                        .font(EKFont.inter(16, .bold))
                    Spacer()
                }
                .foregroundStyle(EKColor.pillYellowFg)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(EKColor.pillYellowBg))
            }
        }
        .padding(22)
    }

    // MARK: Done

    private var doneView: some View {
        let t: HFTally = HFTallies.counts(votes)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Pill("\(t.yes) yes")
                Pill("\(t.maybe) maybe", background: EKColor.pillYellowBg, foreground: EKColor.pillYellowFg)
                Pill("\(t.no) no", background: EKColor.pillGrayBg, foreground: EKColor.pillGrayFg)
            }
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage)
                PrimaryButton("Try again", isLoading: submitting) { submit() }
                    .accessibilityIdentifier("retryTimeVotesButton")
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(EKColor.teal)
                    Text("Sending your swipes…")
                        .font(EKFont.callout)
                        .foregroundStyle(EKColor.muted)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        errorMessage = nil
        let snapshot: [String: Vote] = votes
        Task { @MainActor in
            do {
                try await env.hangouts.submitTimeVotes(hangoutId: hangoutId, uid: uid, votes: snapshot)
                HFLocalStore.addVotedSlotIds(Array(snapshot.keys), hangoutId: hangoutId, uid: uid)
            } catch {
                errorMessage = error.localizedDescription
            }
            submitting = false
        }
    }
}

// MARK: - Screen 08a: one-day availability + suggest a time (KAL-27, KAL-28)

@MainActor
struct HFDayAvailabilityView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String
    let referenceSlot: TimeSlot?

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var day: Date
    /// "Your idea" block, minutes from midnight.
    @State private var ideaStart: Int
    @State private var ideaDuration: Int
    @State private var dragAnchor: Int? = nil
    @State private var sending: Bool = false
    @State private var sentRange: String? = nil
    @State private var errorMessage: String? = nil

    private let firstHour: Int = 8
    private let lastHour: Int = 23
    private let hourHeight: CGFloat = 26
    private let labelWidth: CGFloat = 30
    private let calendar: Calendar = Calendar.current

    private static let laneColors: [Color] = [
        Color(hex: "#E8ECEC"), Color(hex: "#FFCC00"), Color(hex: "#CB30E0"),
        Color(hex: "#6E8BFF"), Color(hex: "#00C3D0"), Color(hex: "#FF8A5B"),
        Color(hex: "#9BE07A"), Color(hex: "#F48FB1"),
    ]

    init(store: HFHangoutStore, uid: String, hangoutId: String, referenceSlot: TimeSlot?, fallbackDay: Date? = nil) {
        self.store = store
        self.uid = uid
        self.hangoutId = hangoutId
        self.referenceSlot = referenceSlot
        let cal: Calendar = Calendar.current
        let anchor: Date = referenceSlot?.start ?? fallbackDay ?? Date().addingTimeInterval(86_400)
        _day = State(initialValue: cal.startOfDay(for: anchor))
        var duration: Int = 60
        var start: Int = 18 * 60
        if let slot = referenceSlot {
            duration = max(30, Int((slot.end.timeIntervalSince(slot.start) / 60).rounded()))
            start = HFDayMath.minutesIntoDay(slot.start, calendar: cal) + duration + 60
        } else if let first = store.hangout?.durationsMinutes.min() {
            duration = first
        }
        _ideaDuration = State(initialValue: duration)
        _ideaStart = State(initialValue: HFDayMath.clampStart(HFDayMath.snap(Double(start)), duration: duration,
                                                              dayStart: 8 * 60, dayEnd: 23 * 60))
    }

    // MARK: Derived

    private var lanes: [HFLane] { store.lanes(myUid: uid) }
    private var gridHeight: CGFloat { CGFloat(lastHour - firstHour) * hourHeight }
    private var ideaStartDate: Date { HFDayMath.date(day: day, minutes: ideaStart, calendar: calendar) }
    private var ideaEndDate: Date { HFDayMath.date(day: day, minutes: ideaStart + ideaDuration, calendar: calendar) }
    private var clashNames: [String] { HFDayMath.clashes(start: ideaStartDate, end: ideaEndDate, lanes: lanes) }
    private var isPast: Bool { ideaStartDate < Date().addingTimeInterval(60 * 60) }
    private var rangeText: String { HFFormat.timeRange(ideaStartDate, ideaEndDate) }

    private var durationOptions: [Int] {
        var set: Set<Int> = Set(store.hangout?.durationsMinutes ?? [])
        if set.isEmpty { set = [60, 120] }
        set.insert(ideaDuration)
        return set.filter { $0 > 0 && $0 <= (lastHour - firstHour) * 60 }.sorted()
    }

    private var minDay: Date { calendar.startOfDay(for: Date()) }
    private var maxDay: Date { calendar.date(byAdding: .day, value: 30, to: minDay) ?? minDay }

    private var otherNames: [String] {
        store.inGroup.filter { $0.id != uid }.map { HFFormat.firstName($0.name) }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Back to swiping")
                            .font(EKFont.body)
                    }
                    .foregroundStyle(EKColor.textPrimary)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dayViewBack")
                Spacer()
            }
            .padding(.horizontal, EKSpacing.screen - 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VStack(spacing: 8) {
                        laneHeader
                        grid
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(EKColor.sheet))
                    if let sentRange = sentRange {
                        sentCard(sentRange)
                    } else {
                        controls
                    }
                    if let errorMessage = errorMessage {
                        ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }
                }
                .padding(.horizontal, EKSpacing.screen)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if sentRange == nil {
                    FloatingFooter { sendButton }
                }
            }
        }
        .ekScreenBackground()
        .foregroundStyle(EKColor.textPrimary)
        .accessibilityIdentifier("dayView")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("\(store.displayName(uid: uid)) · Availability")
            HStack(spacing: 8) {
                Text(HFFormat.dayHeader(day))
                    .font(EKFont.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                dayButton(systemImage: "chevron.left", delta: -1)
                    .disabled(day <= minDay)
                dayButton(systemImage: "chevron.right", delta: 1)
                    .disabled(day >= maxDay)
            }
            Text(subtitleText)
                .font(EKFont.inter(14))
                .foregroundStyle(EKColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitleText: String {
        if let slot = referenceSlot, calendar.isDate(slot.start, inSameDayAs: day) {
            return "Suggested \(HFFormat.timeRange(slot.start, slot.end)) · Tap or drag on the calendar to try another time"
        }
        return "Busy times only, never what’s on anyone’s calendar. Tap or drag to try a time."
    }

    private func dayButton(systemImage: String, delta: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .day, value: delta, to: day) {
                day = calendar.startOfDay(for: next)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(EKColor.raised))
        }
        .buttonStyle(.plain)
    }

    private var laneHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth, height: 1)
            ForEach(Array(lanes.enumerated()), id: \.offset) { pair in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(laneColor(pair.offset))
                        .frame(width: 10, height: 10)
                    Text(pair.element.name)
                        .font(EKFont.inter(12, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func laneColor(_ index: Int) -> Color {
        HFDayAvailabilityView.laneColors[index % HFDayAvailabilityView.laneColors.count]
    }

    private func y(_ minute: Int) -> CGFloat {
        CGFloat(minute - firstHour * 60) / 60.0 * hourHeight
    }

    private func h(_ fromMinute: Int, _ toMinute: Int) -> CGFloat {
        max(2, CGFloat(toMinute - fromMinute) / 60.0 * hourHeight)
    }

    /// Busy blocks for this day clipped to the visible hours.
    private func visibleBlocks(_ lane: HFLane) -> [(start: Int, end: Int)] {
        let lo: Int = firstHour * 60
        let hi: Int = lastHour * 60
        var out: [(start: Int, end: Int)] = []
        for b in HFDayMath.dayBlocks(lane.busy, day: day, calendar: calendar) {
            let s: Int = max(lo, b.start)
            let e: Int = min(hi, b.end)
            if e > s { out.append((start: s, end: e)) }
        }
        return out
    }

    private var grid: some View {
        GeometryReader { geo in
            let width: CGFloat = geo.size.width
            let laneWidth: CGFloat = (width - labelWidth) / CGFloat(max(1, lanes.count))
            ZStack(alignment: .topLeading) {
                hourLines(width: width)
                ForEach(Array(lanes.enumerated()), id: \.offset) { pair in
                    laneBlocks(pair.element, index: pair.offset, laneWidth: laneWidth)
                }
                referenceHighlight(width: width)
                ideaBlock(width: width)
            }
            .frame(width: width, height: gridHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(dragGesture)
        }
        .frame(height: gridHeight)
    }

    private func hourLines(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(firstHour...lastHour), id: \.self) { hour in
                Rectangle()
                    .fill(Color(hex: "#1A2527"))
                    .frame(width: max(0, width - labelWidth), height: 1)
                    .offset(x: labelWidth, y: y(hour * 60))
                if hour % 2 == 0 && hour < lastHour {
                    Text(HFFormat.hourLabel(hour))
                        .font(EKFont.inter(11))
                        .foregroundStyle(EKColor.placeholder)
                        .frame(width: labelWidth - 2, alignment: .leading)
                        .offset(x: 0, y: y(hour * 60) - 6)
                }
            }
        }
    }

    private func laneBlocks(_ lane: HFLane, index: Int, laneWidth: CGFloat) -> some View {
        let color: Color = laneColor(index)
        let x: CGFloat = labelWidth + CGFloat(index) * laneWidth + 2
        let blocks: [(start: Int, end: Int)] = visibleBlocks(lane)
        let buffer: Int = max(0, lane.bufferMinutes)
        let lo: Int = firstHour * 60
        let hi: Int = lastHour * 60
        return ZStack(alignment: .topLeading) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { pair in
                let b: (start: Int, end: Int) = pair.element
                let bs: Int = max(lo, b.start - buffer)
                let be: Int = min(hi, b.end + buffer)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: max(0, laneWidth - 4), height: h(bs, be))
                    .offset(x: x, y: y(bs))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color)
                    .frame(width: max(0, laneWidth - 4), height: h(b.start, b.end))
                    .overlay(alignment: .top) {
                        if b.end - b.start >= 45 {
                            Text("Busy")
                                .font(EKFont.inter(10, .bold))
                                .foregroundStyle(EKColor.avatarText)
                                .padding(.top, 3)
                        }
                    }
                    .offset(x: x, y: y(b.start))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func referenceHighlight(width: CGFloat) -> some View {
        if let slot = referenceSlot, calendar.isDate(slot.start, inSameDayAs: day) {
            let s: Int = max(firstHour * 60, HFDayMath.minutesIntoDay(slot.start, calendar: calendar))
            let e: Int = min(lastHour * 60, s + max(15, Int(slot.end.timeIntervalSince(slot.start) / 60)))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(EKColor.teal.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(EKColor.teal, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Text("Suggested · \(HFFormat.shortTime(slot.start))–\(HFFormat.shortTime(slot.end))")
                        .font(EKFont.inter(11, .heavy))
                        .foregroundStyle(EKColor.pillTealFg)
                        .padding(4)
                }
                .frame(width: max(0, width - labelWidth), height: h(s, e))
                .offset(x: labelWidth, y: y(s))
                .allowsHitTesting(false)
        }
    }

    /// My lane's color (my lane is listed first), so "Your idea" matches my column.
    private var myColor: Color {
        laneColor(lanes.firstIndex(where: { $0.uid == uid }) ?? 0)
    }

    private func ideaBlock(width: CGFloat) -> some View {
        let ok: Bool = clashNames.isEmpty && !isPast
        let accent: Color = ok ? myColor : Color(hex: "#FF8A65")
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(accent.opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .overlay(alignment: .topLeading) {
                Text("Your idea · \(HFFormat.shortTime(ideaStartDate))–\(HFFormat.shortTime(ideaEndDate))")
                    .font(EKFont.inter(12, .heavy))
                    .foregroundStyle(EKColor.textPrimary)
                    .padding(5)
            }
            .frame(width: max(0, width - labelWidth), height: h(ideaStart, ideaStart + ideaDuration))
            .shadow(color: Color.black.opacity(dragAnchor == nil ? 0 : 0.5), radius: 10, y: 6)
            .offset(x: labelWidth, y: y(ideaStart))
            .animation(dragAnchor == nil ? Animation.easeOut(duration: 0.15) : nil, value: ideaStart)
            .accessibilityElement()
            .accessibilityLabel("Your idea, \(rangeText)")
            .accessibilityIdentifier("ideaBlock")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: move(by: 15)
                case .decrement: move(by: -15)
                @unknown default: break
                }
            }
    }

    private func minuteAt(y: CGFloat) -> Int {
        firstHour * 60 + Int((y / hourHeight * 60).rounded())
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard sentRange == nil else { return }
                let minute: Int = minuteAt(y: value.location.y)
                if dragAnchor == nil {
                    if minute >= ideaStart && minute <= ideaStart + ideaDuration {
                        dragAnchor = minute - ideaStart          // grabbed the block: keep the offset
                    } else {
                        dragAnchor = ideaDuration / 2            // tapped elsewhere: center it there
                    }
                }
                let raw: Double = Double(minute - (dragAnchor ?? 0))
                ideaStart = HFDayMath.clampStart(HFDayMath.snap(raw), duration: ideaDuration,
                                                 dayStart: firstHour * 60, dayEnd: lastHour * 60)
            }
            .onEnded { _ in
                dragAnchor = nil
            }
    }

    private func move(by minutes: Int) {
        ideaStart = HFDayMath.clampStart(ideaStart + minutes, duration: ideaDuration,
                                         dayStart: firstHour * 60, dayEnd: lastHour * 60)
    }

    private func setDuration(_ minutes: Int) {
        ideaDuration = minutes
        ideaStart = HFDayMath.clampStart(ideaStart, duration: minutes, dayStart: firstHour * 60, dayEnd: lastHour * 60)
    }

    // MARK: Controls

    private var controls: some View {
        let ok: Bool = clashNames.isEmpty
        let statusText: String = isPast ? "Too soon" : HFDayMath.statusText(clashNames: clashNames)
        let statusColor: Color = (ok && !isPast) ? EKColor.teal : Color(hex: "#FF8A65")
        return Card(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Suggest another time")
                        .font(EKFont.inter(17, .bold))
                    Spacer()
                    Text(statusText)
                        .font(EKFont.inter(13, .bold))
                        .foregroundStyle(statusColor)
                        .accessibilityIdentifier("ideaStatus")
                }
                HStack {
                    stepButton("minus", label: "Earlier") { move(by: -15) }
                    Spacer()
                    Text(rangeText)
                        .font(EKFont.inter(20, .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    stepButton("plus", label: "Later") { move(by: 15) }
                }
                FlowLayout(spacing: 8) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Chip(HFFormat.durationLabel(minutes: minutes), isSelected: minutes == ideaDuration) {
                            setDuration(minutes)
                        }
                    }
                }
                if isPast {
                    Text("Pick a time at least an hour from now.")
                        .font(EKFont.inter(13))
                        .foregroundStyle(EKColor.muted)
                }
            }
        }
    }

    /// Floats at the bottom of the day view while picking a time.
    private var sendButton: some View {
        Group {
            if clashNames.isEmpty {
                PrimaryButton("Send to the group", isLoading: sending) { send() }
            } else {
                SecondaryButton("Send anyway", isLoading: sending) { send() }
            }
        }
        .disabled(isPast || sending)
        .accessibilityIdentifier("suggestTimeButton")
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(EKColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(EKColor.raised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func sentCard(_ range: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(EKColor.teal)
                Text(otherNames.isEmpty ? "Sent to the group" : "Sent to \(HFFormat.joinNames(otherNames))")
                    .font(EKFont.inter(17, .bold))
            }
            Text("\(range) will show up as a new time for everyone to swipe on.")
                .font(EKFont.inter(14))
                .foregroundStyle(EKColor.pillTealFg)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Suggest another") { sentRange = nil }
                    .buttonStyle(LinkButtonStyle())
                Spacer()
                Button("Back to swiping") { dismiss() }
                    .buttonStyle(LinkButtonStyle(color: EKColor.textPrimary))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(hex: "#13292B")))
        .accessibilityIdentifier("suggestionSent")
    }

    private func send() {
        let start: Date = ideaStartDate
        let end: Date = ideaEndDate
        let label: String = "\(HFFormat.dayHeader(start)) \(HFFormat.timeRange(start, end))"
        sending = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await env.functions.suggestTime(hangoutId: hangoutId, start: start, end: end)
                sentRange = label
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = false
        }
    }
}

// MARK: - Screen 08b: no mutual time (KAL-29)

@MainActor
struct HFNoTimesView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String
    let onCancelHangout: () -> Void

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var picked: Set<String> = []
    @State private var sending: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showDayView: Bool = false

    private var offers: [TimeSlot] { store.offerSlots }
    private var everyoneFree: [TimeSlot] { offers.filter { $0.missingMemberIds.isEmpty } }
    private var allButOne: [TimeSlot] { offers.filter { !$0.missingMemberIds.isEmpty } }

    private var title: String {
        let n: Int = store.inGroup.count
        if n <= 2 { return "No time works for both of you." }
        return "No time works for all \(HFFormat.numberWord(n)) of you."
    }

    private var subtitle: String {
        if offers.isEmpty {
            return "Nobody’s calendars line up in the next month. Suggest a time that almost works and the group will swipe on it."
        }
        return "So we looked out a full month. Pick any that could work and the group will swipe on them."
    }

    private var cta: String {
        let n: Int = picked.count
        if n == 0 { return "Pick at least one" }
        return "Send \(n) \(n == 1 ? "option" : "options") to the group"
    }

    var body: some View {
        ScreenScaffold(title: title, subtitle: subtitle,
                       eyebrow: "\(store.displayName(uid: uid)) · Picking a time") {
            if !everyoneFree.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Later this month · everyone free")
                    ForEach(everyoneFree) { slot in offerRow(slot) }
                }
            }
            if !allButOne.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("All but one", color: EKColor.yellow)
                    ForEach(allButOne) { slot in offerRow(slot) }
                }
            }
            if store.isOwner(uid) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("Owner options", color: EKColor.placeholder)
                    Text("You can also remove someone from the waiting list later, or call it off.")
                        .font(EKFont.inter(13))
                        .foregroundStyle(EKColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Cancel hangout", action: onCancelHangout)
                        .buttonStyle(LinkButtonStyle(color: EKColor.dangerText))
                        .accessibilityIdentifier("noTimesCancelButton")
                }
            }
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            VStack(spacing: 10) {
                if !offers.isEmpty {
                    PrimaryButton(cta, isLoading: sending) { sendPicked() }
                        .disabled(picked.isEmpty)
                        .accessibilityIdentifier("sendOffersButton")
                }
                SecondaryButton("Suggest a different time", systemImage: "calendar") { showDayView = true }
                    .accessibilityIdentifier("suggestDifferentTimeButton")
            }
        }
        .accessibilityIdentifier("noTimesView")
        .fullScreenCover(isPresented: $showDayView) {
            HFDayAvailabilityView(store: store, uid: uid, hangoutId: hangoutId, referenceSlot: nil,
                                  fallbackDay: offers.first?.start)
                .environment(env)
        }
    }

    private func offerRow(_ slot: TimeSlot) -> some View {
        let on: Bool = picked.contains(slot.id)
        let missing: [String] = slot.missingMemberIds.map { store.memberName($0) }
        return Button {
            if on { picked.remove(slot.id) } else { picked.insert(slot.id) }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(HFFormat.dayHeader(slot.start))
                        .font(EKFont.inter(16, .bold))
                        .foregroundStyle(EKColor.textPrimary)
                    Text(HFFormat.timeRange(slot.start, slot.end))
                        .font(EKFont.inter(14))
                        .foregroundStyle(EKColor.muted)
                    if !missing.isEmpty {
                        Text("\(HFFormat.joinNames(missing)) can’t make it")
                            .font(EKFont.inter(13, .bold))
                            .foregroundStyle(EKColor.yellow)
                    }
                }
                Spacer()
                HFCheckBox(isOn: on)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(on ? Color(hex: "#13292B") : EKColor.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(on ? EKColor.teal : EKColor.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("offer_\(slot.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sendPicked() {
        let chosen: [TimeSlot] = offers.filter { picked.contains($0.id) }.sorted { $0.start < $1.start }
        guard !chosen.isEmpty else { return }
        sending = true
        errorMessage = nil
        Task { @MainActor in
            do {
                for slot in chosen {
                    try await env.functions.suggestTime(hangoutId: hangoutId, start: slot.start, end: slot.end)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = false
        }
    }
}
