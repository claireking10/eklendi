import SwiftUI

// MARK: - Screen 09: activity survey (KAL-30, KAL-31)

@MainActor
struct HFSurveyView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var answers: [String: SurveyAnswer] = [:]
    @State private var finished: Bool = false
    @State private var submitting: Bool = false
    @State private var errorMessage: String? = nil

    private let questions: [SurveyQuestion] = SurveyQuestion.all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HFHeader(eyebrow: "\(store.displayName(uid: uid)) · Step 2 of 3",
                     title: finished ? "Got it. That’s all we need." : "What sounds good?")
            if finished {
                doneView
            } else {
                Text("\(min(answers.count + 1, questions.count)) of \(questions.count)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(EKColor.teal)
                    .accessibilityIdentifier("surveyCounter")
                SwipeCardStack(items: questions, onVote: { question, vote in
                    answers[question.id] = SurveyAnswer(rawValue: vote.rawValue) ?? .maybe
                }, onFinished: {
                    finished = true
                    submit()
                }, skipTitle: "I don’t care", onSkip: { question in
                    answers[question.id] = .dontCare
                }) { question in
                    questionCard(question)
                }
                .frame(maxHeight: .infinity)
                Text("“I don’t care” counts as neutral. It won’t rule anything out.")
                    .font(.system(size: 13))
                    .foregroundStyle(EKColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, EKSpacing.screen)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func questionCard(_ q: SurveyQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(q.category)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(EKColor.pillTealFg)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(EKColor.pillTealBg))
            Spacer()
            Text(q.question)
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(EKColor.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(q.subtitle)
                .font(.system(size: 16))
                .foregroundStyle(EKColor.muted)
                .padding(.top, 10)
            Text(q.examples)
                .font(.system(size: 13))
                .foregroundStyle(EKColor.placeholder)
                .padding(.top, 6)
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneView: some View {
        let skips: Int = answers.values.filter { $0 == .dontCare }.count
        let n: Int = questions.count
        let note: String = skips > 0
            ? "You answered \(n - skips) of \(n) and said “I don’t care” to \(skips). Those stay open, so the group decides."
            : "You answered all \(n). We’ll combine your answers with everyone else’s."
        return VStack(alignment: .leading, spacing: 16) {
            Text(note)
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HFInfoBanner("If most of the group doesn’t care about something, like price, we’ll pick a sensible default for it.",
                         systemImage: "lightbulb")
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage)
                PrimaryButton("Try again", isLoading: submitting) { submit() }
                    .accessibilityIdentifier("retrySurveyButton")
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(EKColor.teal)
                    Text("Sending your answers…")
                        .font(EKFont.callout)
                        .foregroundStyle(EKColor.muted)
                }
            }
            Spacer()
        }
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        errorMessage = nil
        let snapshot: [String: SurveyAnswer] = answers
        Task { @MainActor in
            do {
                try await env.hangouts.submitSurvey(hangoutId: hangoutId, uid: uid, answers: snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
            submitting = false
        }
    }
}

// MARK: - Screen 11: hangout cards (KAL-37)

@MainActor
struct HFCardsView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var votes: [String: Vote] = [:]
    @State private var finished: Bool = false
    @State private var submitting: Bool = false
    @State private var errorMessage: String? = nil

    private var round: Int { store.hangout?.round ?? 1 }
    private var cards: [HangoutCard] { store.cards.filter { $0.round == round } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("\(store.displayName(uid: uid)) · Step 3 of 3")
            if finished {
                Text("Your votes are in.")
                    .font(EKFont.title)
                doneView
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pick a hangout.")
                        .font(EKFont.title)
                    Spacer()
                    if !cards.isEmpty {
                        Text("\(min(votes.count + 1, cards.count)) of \(cards.count)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(EKColor.muted)
                            .accessibilityIdentifier("cardsCounter")
                    }
                }
                if cards.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            ProgressView().tint(EKColor.teal)
                            Text("Getting ideas ready…")
                                .font(EKFont.callout)
                                .foregroundStyle(EKColor.muted)
                        }
                        Spacer()
                    }
                    Spacer()
                } else {
                    SwipeCardStack(items: cards, onVote: { card, vote in
                        votes[card.id] = vote
                    }, onFinished: {
                        finished = true
                        submit()
                    }) { card in
                        cardContent(card)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, EKSpacing.screen)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    private func cardContent(_ card: HangoutCard) -> some View {
        var pills: [String] = [HFFormat.durationLabel(card.start, card.end)]
        if let price = HFFormat.priceLabel(card.priceLevel) { pills.append(price) }
        var place: String = card.venueName
        if let distance = HFFormat.distanceLabel(card.distanceMiles) { place += " · \(distance)" }
        return ZStack(alignment: .bottom) {
            HFVenueBackground(photoUrl: card.photoUrl, category: card.category)
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                           startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Text(HFFormat.shortWhen(card.start, card.end))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(EKColor.teal)
                HStack(spacing: 6) {
                    ForEach(pills, id: \.self) { p in
                        Pill(p)
                    }
                }
                Text(card.activity)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(EKColor.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(place)
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EKColor.textSecondary)
                if !card.address.isEmpty {
                    Text(card.address)
                        .font(.system(size: 13))
                        .foregroundStyle(EKColor.muted)
                        .lineLimit(1)
                }
                if !card.description.isEmpty {
                    Text(card.description)
                        .font(.system(size: 14))
                        .foregroundStyle(EKColor.body)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: "#080E0F").opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(12)
        }
    }

    private var doneView: some View {
        let yes: Int = votes.values.filter { $0 == .yes }.count
        return VStack(alignment: .leading, spacing: 16) {
            Text("You said yes to \(yes) of \(votes.count). We’ll show the result as soon as everyone has swiped.")
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage)
                PrimaryButton("Try again", isLoading: submitting) { submit() }
                    .accessibilityIdentifier("retryCardVotesButton")
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(EKColor.teal)
                    Text("Sending your votes…")
                        .font(EKFont.callout)
                        .foregroundStyle(EKColor.muted)
                }
            }
            Spacer()
        }
    }

    private func submit() {
        guard !submitting else { return }
        submitting = true
        errorMessage = nil
        let snapshot: [String: Vote] = votes
        let currentRound: Int = round
        Task { @MainActor in
            do {
                try await env.hangouts.submitCardVotes(hangoutId: hangoutId, uid: uid, round: currentRound, votes: snapshot)
            } catch {
                errorMessage = error.localizedDescription
            }
            submitting = false
        }
    }
}

// MARK: - Screen 11a: not everyone agrees (KAL-41)

@MainActor
struct HFNoAgreementView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var votes: [String: [String: Vote]] = [:]
    @State private var starting: Bool = false
    @State private var errorMessage: String? = nil

    private var round: Int { store.hangout?.round ?? 1 }
    private var cards: [HangoutCard] { store.cards.filter { $0.round == round } }
    private var voters: [HangoutMember] {
        let group: [HangoutMember] = store.participants
        return group.filter { $0.id == uid } + group.filter { $0.id != uid }
    }

    private var topCards: [HangoutCard] {
        let list: [HangoutCard] = cards
        let ids: [String] = HFTallies.topOptions(
            optionIds: list.map { $0.id },
            startOf: { id in list.first(where: { $0.id == id })?.start ?? Date.distantFuture },
            votes: votes,
            voters: voters.map { $0.id })
        return ids.compactMap { id in list.first(where: { $0.id == id }) }
    }

    private var nextCount: Int { max(2, voters.count) * 3 }

    private var subtitle: String {
        let n: Int = voters.count
        let who: String = n <= 2 ? "both of you" : "all \(HFFormat.numberWord(n)) of you"
        return "No idea got a yes or maybe from \(who). Here’s what came closest."
    }

    var body: some View {
        ScreenScaffold(title: "Not everyone agrees yet.", subtitle: subtitle,
                       eyebrow: "\(store.displayName(uid: uid)) · Round \(round) results") {
            if let msg = store.hangout?.statusMessage, !msg.isEmpty {
                HFInfoBanner(msg, systemImage: "exclamationmark.triangle", tint: EKColor.yellow,
                             background: EKColor.pillYellowBg, border: EKColor.pillYellowBg,
                             foreground: EKColor.pillYellowFg)
            }
            VStack(spacing: 12) {
                ForEach(topCards) { card in
                    resultRow(card)
                }
            }
            HFInfoBanner("Next round: \(nextCount) new ideas, 3 for each person in the group. Swipe the same way as before.",
                         systemImage: "arrow.triangle.2.circlepath")
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            PrimaryButton("Swipe on \(nextCount) new ideas", isLoading: starting) { startNewRound() }
                .accessibilityIdentifier("newRoundButton")
        }
        .accessibilityIdentifier("noAgreementView")
        .task(id: round) {
            do {
                votes = try await env.hangouts.cardVotes(hangoutId: hangoutId, round: round)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func voteColor(_ vote: Vote?) -> Color {
        switch vote {
        case .some(.yes): return EKColor.teal
        case .some(.maybe): return EKColor.yellow
        default: return EKColor.noRing
        }
    }

    private func resultRow(_ card: HangoutCard) -> some View {
        let tally: HFTally = HFTallies.tally(optionId: card.id, votes: votes, voters: voters.map { $0.id })
        return HStack(alignment: .top, spacing: 14) {
            HFVenueBackground(photoUrl: card.photoUrl, category: card.category)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(card.activity)
                    .font(.system(size: 17, weight: .heavy))
                    .lineLimit(2)
                Text(tally.label)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(EKColor.teal)
                Text("\(card.venueName) · \(HFFormat.shortDayTime(card.start))")
                    .font(.system(size: 13))
                    .foregroundStyle(EKColor.muted)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ForEach(voters) { m in
                        let vote: Vote? = votes[m.id]?[card.id]
                        Avatar(name: m.name, size: 28)
                            .overlay(alignment: .bottomTrailing) {
                                Circle()
                                    .fill(voteColor(vote))
                                    .frame(width: 11, height: 11)
                                    .overlay(Circle().stroke(EKColor.card, lineWidth: 2))
                            }
                            .accessibilityLabel("\(HFFormat.shortName(m, myUid: uid)) said \(vote?.rawValue ?? "nothing")")
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(EKColor.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1))
    }

    private func startNewRound() {
        starting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await env.functions.startNewRound(hangoutId: hangoutId)
            } catch {
                errorMessage = error.localizedDescription
            }
            starting = false
        }
    }
}

// MARK: - Screen 12: it's a plan (KAL-42, KAL-43, KAL-44)

@MainActor
struct HFMatchView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    private enum CalendarState: Equatable {
        case idle
        case adding
        case added
        case failed(String)
    }

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var calendarState: CalendarState = .idle
    @State private var toggling: Bool = false
    @State private var errorMessage: String? = nil

    private var hangout: Hangout? { store.hangout }
    private var plan: ConfirmedPlan? { store.hangout?.confirmed }
    private var me: HangoutMember? { store.me(uid) }
    private var notGoing: Bool { me?.notGoing ?? false }
    private var isTimeOnly: Bool { hangout?.mode == .timeOnly }
    private var card: HangoutCard? {
        guard let id = plan?.cardId else { return nil }
        return store.cards.first { $0.id == id }
    }

    private var going: [HangoutMember] {
        let group: [HangoutMember] = store.participants
        return group.filter { $0.id == uid } + group.filter { $0.id != uid }
    }

    private var eventTitle: String {
        let title: String = hangout?.title ?? ""
        if !title.isEmpty { return title }
        let activity: String = plan?.activity ?? ""
        return activity.isEmpty ? "Hangout" : activity
    }

    private var eventLocation: String? {
        guard let p = plan, !p.venueName.isEmpty else { return nil }
        return p.address.isEmpty ? p.venueName : "\(p.venueName), \(p.address)"
    }

    private var calendarKey: String {
        "\(hangoutId)-\(plan?.start.timeIntervalSince1970 ?? 0)-\(notGoing)"
    }

    var body: some View {
        if let p = plan {
            ScreenScaffold(title: "It’s a plan.",
                           subtitle: "Everyone agreed, so it’s confirmed. It goes straight into everyone’s calendar.",
                           eyebrow: "\(store.displayName(uid: uid)) · Confirmed") {
                details(p)
                if notGoing {
                    HFInfoBanner("We let \(otherNamesText) know you can’t make it. The plan stays the same for them.",
                                 systemImage: "exclamationmark.circle", tint: EKColor.yellow,
                                 background: Color(hex: "#2A2113"), border: Color(hex: "#4A3F12"),
                                 foreground: EKColor.pillYellowFg)
                }
                calendarRow
                membersCard
                if let errorMessage = errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                }
            } footer: {
                SecondaryButton(notGoing ? "Actually, I can make it" : "I’m no longer available", isLoading: toggling) {
                    toggleNotGoing()
                }
                .accessibilityIdentifier("notGoingButton")
            }
            .accessibilityIdentifier("matchView")
            .task(id: calendarKey) {
                await syncCalendar()
            }
        } else {
            LoadingView()
        }
    }

    private var otherNamesText: String {
        let names: [String] = going.filter { $0.id != uid }.map { HFFormat.firstName($0.name) }
        return names.isEmpty ? "the group" : HFFormat.joinNames(names)
    }

    private func details(_ p: ConfirmedPlan) -> some View {
        var line: String = HFFormat.timeRange(p.start, p.end)
        if !p.venueName.isEmpty { line += " · \(p.venueName)" }
        if let d = HFFormat.distanceLabel(card?.distanceMiles) { line += " · \(d)" }
        return VStack(alignment: .leading, spacing: 0) {
            if !isTimeOnly {
                HFVenueBackground(photoUrl: card?.photoUrl, category: card?.category ?? "")
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(HFFormat.longDate(p.start))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(EKColor.teal)
                    Spacer()
                    Pill(HFFormat.durationLabel(p.start, p.end))
                }
                Text(p.activity.isEmpty ? eventTitle : p.activity)
                    .font(.system(size: 26, weight: .black))
                    .fixedSize(horizontal: false, vertical: true)
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(EKColor.body)
                if !p.address.isEmpty {
                    Text(p.address)
                        .font(.system(size: 13))
                        .foregroundStyle(EKColor.muted)
                }
                if isTimeOnly {
                    Text("Just a time. The plan is on the calendar invite.")
                        .font(.system(size: 13))
                        .foregroundStyle(EKColor.muted)
                }
            }
            .padding(18)
        }
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(EKColor.card))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planDetails")
    }

    private var calendarRow: some View {
        Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: calendarIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(calendarTint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendarTitle)
                        .font(.system(size: 15, weight: .bold))
                    if let message = calendarFailure {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(EKColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                if calendarState == .adding {
                    ProgressView().tint(EKColor.teal)
                } else if calendarFailure != nil {
                    Button("Add") {
                        Task { @MainActor in await syncCalendar() }
                    }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("addToCalendarButton")
                }
            }
        }
        .accessibilityIdentifier("calendarStatus")
    }

    private var calendarFailure: String? {
        switch calendarState {
        case .failed(let message): return message
        default: return nil
        }
    }

    private var calendarIcon: String {
        switch calendarState {
        case .added: return "calendar.badge.checkmark"
        case .failed: return "calendar.badge.exclamationmark"
        default: return "calendar"
        }
    }

    private var calendarTint: Color {
        switch calendarState {
        case .added: return EKColor.teal
        case .failed: return EKColor.yellow
        default: return EKColor.muted
        }
    }

    private var calendarTitle: String {
        if notGoing { return "Not on your calendar while you can’t go" }
        switch calendarState {
        case .idle: return "Your calendar"
        case .adding: return "Adding to your calendar…"
        case .added: return "Added to your calendar"
        case .failed: return "Couldn’t add it to your calendar"
        }
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader("Who’s going")
                Spacer()
                Text("\(going.filter { !$0.notGoing }.count) of \(going.count) going")
                    .font(.system(size: 13))
                    .foregroundStyle(EKColor.muted)
            }
            Card(padding: 0, cornerRadius: 18) {
                VStack(spacing: 0) {
                    ForEach(going) { m in
                        HStack(spacing: 12) {
                            Avatar(name: m.name, size: 34)
                            Text(m.id == uid ? "You" : m.name)
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Text(m.notGoing ? "Not going" : "Going")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(m.notGoing ? EKColor.yellow : EKColor.teal)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        if m.id != going.last?.id {
                            Rectangle().fill(EKColor.cardBorder).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func toggleNotGoing() {
        let newValue: Bool = !notGoing
        toggling = true
        Task { @MainActor in
            do {
                try await env.hangouts.setNotGoing(hangoutId: hangoutId, uid: uid, notGoing: newValue)
            } catch {
                errorMessage = error.localizedDescription
            }
            toggling = false
        }
    }

    /// Adds the confirmed hangout to my calendar once (remembered per hangout + start time);
    /// takes it off again while I'm not going.
    @MainActor
    private func syncCalendar() async {
        guard let p = plan else { return }
        let record: (start: Double, identifier: String)? = HFLocalStore.calendarEvent(hangoutId: hangoutId)
        if notGoing {
            if let record = record {
                try? await env.calendar.removeEvent(identifier: record.identifier)
                HFLocalStore.clearCalendarEvent(hangoutId: hangoutId)
            }
            calendarState = .idle
            return
        }
        if let record = record, record.start == p.start.timeIntervalSince1970 {
            calendarState = .added
            return
        }
        calendarState = .adding
        do {
            if !env.calendar.isAuthorized {
                let granted: Bool = try await env.calendar.requestAccess()
                if !granted { throw HFError("Calendar access is off. Turn it on in Settings › Privacy › Calendars.") }
            }
            if let record = record {
                try? await env.calendar.removeEvent(identifier: record.identifier)
            }
            let identifier: String = try await env.calendar.addEvent(title: eventTitle, start: p.start, end: p.end,
                                                                     location: eventLocation)
            HFLocalStore.setCalendarEvent(hangoutId: hangoutId, start: p.start, identifier: identifier)
            calendarState = .added
        } catch {
            calendarState = .failed(error.localizedDescription)
        }
    }
}
