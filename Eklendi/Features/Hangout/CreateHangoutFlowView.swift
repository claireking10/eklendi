import SwiftUI

/// "Plan a hangout": 05 Invite friends → 05a What to decide → 06 How long. Creating the
/// hangout replaces this flow with HangoutFlowView for the new id (KAL-17, KAL-18, KAL-19).
@MainActor
struct CreateHangoutFlowView: View {
    let uid: String

    private enum Step: Int { case invite, plan, constraints }

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(TabRouter.self) private var router: TabRouter
    @Environment(\.dismiss) private var dismiss: DismissAction

    @State private var step: Step = .invite
    @State private var profile: UserProfile? = nil
    @State private var friends: [UserProfile] = []
    @State private var loading: Bool = true
    @State private var picked: Set<String> = []
    @State private var mode: HangoutMode = .timeAndActivity
    @State private var planDescription: String = ""
    @State private var presetMinutes: Set<Int> = [60]
    @State private var customOn: Bool = false
    @State private var customHours: Int = HFDurations.defaultCustomHours
    @State private var durationAny: Bool = false
    @State private var creating: Bool = false
    @State private var errorMessage: String? = nil

    static let maxInvitees: Int = 7

    init(uid: String) {
        self.uid = uid
    }

    var body: some View {
        Group {
            switch step {
            case .invite: inviteStep
            case .plan: planStep
            case .constraints: constraintsStep
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
        .errorBanner($errorMessage)
        .task {
            await load()
        }
    }

    private func goBack() {
        switch step {
        case .invite: dismiss()
        case .plan: step = .invite
        case .constraints: step = .plan
        }
    }

    // MARK: 05 Invite friends

    private var inviteCTA: String {
        let n: Int = picked.count
        if n == 0 { return "Pick at least one friend" }
        return "Invite \(n) \(n == 1 ? "friend" : "friends")"
    }

    private var inviteStep: some View {
        ScreenScaffold(title: "New hangout", showsBack: true, onBack: { goBack() }) {
            HFInfoBanner("We’ll look for times over the next 2 weeks, and up to a month if nothing fits.",
                         systemImage: "calendar")
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("Who’s coming?")
                    Spacer()
                    Text("\(picked.count) selected")
                        .font(.system(size: 14))
                        .foregroundStyle(EKColor.muted)
                        .fixedSize()
                }
                if loading {
                    HStack {
                        Spacer()
                        ProgressView().tint(EKColor.teal)
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else if friends.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No friends yet")
                                .font(EKFont.bodyBold)
                            Text("Add friends from your contacts first, then come back to plan.")
                                .font(EKFont.callout)
                                .foregroundStyle(EKColor.muted)
                            Button("Go to Friends") { router.select(.friends) }
                                .buttonStyle(LinkButtonStyle())
                        }
                    }
                } else {
                    Card(padding: 4, cornerRadius: 18) {
                        VStack(spacing: 0) {
                            ForEach(friends) { friend in
                                friendRow(friend)
                            }
                        }
                    }
                    if picked.count >= CreateHangoutFlowView.maxInvitees {
                        Text("That’s the max: hangouts have up to 8 people, including you.")
                            .font(.system(size: 13))
                            .foregroundStyle(EKColor.yellow)
                    }
                }
            }
        } footer: {
            VStack(spacing: 10) {
                Text("Friends get a notification to start swiping.")
                    .font(.system(size: 13))
                    .foregroundStyle(EKColor.muted)
                PrimaryButton(inviteCTA) { step = .plan }
                    .disabled(picked.isEmpty)
                    .accessibilityIdentifier("inviteContinueButton")
            }
        }
    }

    private func friendRow(_ friend: UserProfile) -> some View {
        let on: Bool = picked.contains(friend.id)
        let full: Bool = picked.count >= CreateHangoutFlowView.maxInvitees
        return Button {
            if on {
                picked.remove(friend.id)
            } else if !full {
                picked.insert(friend.id)
            }
        } label: {
            HStack(spacing: 14) {
                Avatar(name: friend.name, photoURL: friend.photoURL, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                    if let home = friend.homeLocation?.text, !home.isEmpty {
                        Text(home)
                            .font(.system(size: 13))
                            .foregroundStyle(EKColor.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HFCheckBox(isOn: on)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .opacity(!on && full ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("friendRow_\(friend.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 05a What do you need help with?

    private var planValid: Bool {
        mode == .timeAndActivity || !planDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var nextSteps: [String] {
        mode == .timeAndActivity
            ? ["Duration", "Starting point", "Swipe on times", "Activity questions", "Vote on ideas", "Confirmed"]
            : ["Duration", "Swipe on times", "Confirmed"]
    }

    private var planStep: some View {
        ScreenScaffold(title: "What do you need help with?",
                       subtitle: "Pick what the group should figure out together.",
                       showsBack: true, onBack: { goBack() }) {
            VStack(spacing: 12) {
                HFRadioOption(title: "A time and an activity",
                              detail: "We’ll find when everyone’s free and suggest things to do nearby.",
                              systemImage: "sparkles",
                              isSelected: mode == .timeAndActivity) {
                    mode = .timeAndActivity
                }
                .accessibilityIdentifier("modeTimeAndActivity")
                HFRadioOption(title: "Just a time",
                              detail: "You already have something in mind. We’ll only find when everyone’s free.",
                              systemImage: "clock",
                              isSelected: mode == .timeOnly) {
                    mode = .timeOnly
                }
                .accessibilityIdentifier("modeTimeOnly")
            }
            if mode == .timeOnly {
                VStack(alignment: .leading, spacing: 6) {
                    EKTextField("e.g. Dinner at Mom’s place", text: $planDescription,
                                label: "What’s the plan?", accessibilityId: "planDescriptionField")
                    Text("Goes on the calendar invite.")
                        .font(.system(size: 13))
                        .foregroundStyle(EKColor.muted)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("What happens next", color: EKColor.placeholder)
                FlowLayout(spacing: 6) {
                    ForEach(Array(nextSteps.enumerated()), id: \.offset) { pair in
                        HStack(spacing: 6) {
                            Text(pair.element)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(EKColor.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(Capsule().fill(EKColor.card))
                            if pair.offset < nextSteps.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(EKColor.placeholder)
                            }
                        }
                    }
                }
            }
        } footer: {
            PrimaryButton("Next") { step = .constraints }
                .disabled(!planValid)
                .accessibilityIdentifier("planNextButton")
        }
    }

    // MARK: 06 How long?

    private var durationsValid: Bool {
        HFDurations.isValid(presets: presetMinutes, customOn: customOn, any: durationAny)
    }

    private var constraintsStep: some View {
        ScreenScaffold(title: "How long should it be?",
                       subtitle: "Pick as many as work. We’ll only suggest times that fit.",
                       showsBack: true, onBack: { goBack() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader("How long?")
                    Spacer()
                    Text(HFDurations.summary(presets: presetMinutes, customOn: customOn,
                                             customHours: customHours, any: durationAny))
                        .font(.system(size: 14))
                        .foregroundStyle(EKColor.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier("durationSummary")
                }
                FlowLayout(spacing: 10) {
                    ForEach(HFDurations.presetMinutes, id: \.self) { minutes in
                        Chip(HFFormat.durationLabel(minutes: minutes),
                             isSelected: !durationAny && presetMinutes.contains(minutes)) {
                            durationAny = false
                            if presetMinutes.contains(minutes) {
                                presetMinutes.remove(minutes)
                            } else {
                                presetMinutes.insert(minutes)
                            }
                        }
                        .accessibilityIdentifier("duration_\(minutes)")
                    }
                    Chip("Custom", isSelected: !durationAny && customOn) {
                        durationAny = false
                        customOn.toggle()
                    }
                    .accessibilityIdentifier("duration_custom")
                }
                if customOn && !durationAny {
                    customStepper
                }
                Chip("I don’t care how long", isSelected: durationAny, style: .dontCare) {
                    durationAny.toggle()
                }
                .accessibilityIdentifier("durationAny")
            }
        } footer: {
            Button {
                create()
            } label: {
                HStack(spacing: 8) {
                    if creating {
                        ProgressView().tint(EKColor.onTeal)
                    }
                    Text("Find times")
                    if !creating {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!durationsValid || creating || profile == nil)
            .accessibilityIdentifier("createHangoutSubmit")
        }
    }

    private var customStepper: some View {
        HStack(spacing: 12) {
            Text("Custom length")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(EKColor.pillTealFg)
            Spacer()
            stepperButton("minus", enabled: customHours > HFDurations.customRange.lowerBound) {
                customHours = HFDurations.clampCustom(customHours - 1)
            }
            .accessibilityLabel("Shorter")
            Text("\(customHours) hr")
                .font(.system(size: 20, weight: .heavy))
                .frame(minWidth: 60)
                .accessibilityIdentifier("customHours")
            stepperButton("plus", enabled: customHours < HFDurations.customRange.upperBound) {
                customHours = HFDurations.clampCustom(customHours + 1)
            }
            .accessibilityLabel("Longer")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#13292B")))
    }

    private func stepperButton(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(EKColor.textPrimary)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(EKColor.raised))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: Data

    @MainActor
    private func load() async {
        loading = true
        do {
            let me: UserProfile? = try await env.users.profile(uid: uid)
            let list: [UserProfile] = try await env.users.friends(of: uid)
            profile = me
            friends = list.sorted { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func create() {
        guard let owner = profile, !creating else { return }
        let invitees: [UserProfile] = friends.filter { picked.contains($0.id) }
        let durations: [Int] = HFDurations.minutes(presets: presetMinutes, customOn: customOn,
                                                   customHours: customHours, any: durationAny)
        let plan: String = mode == .timeOnly ? planDescription.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let chosenMode: HangoutMode = mode
        let any: Bool = durationAny
        creating = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let id: String = try await env.hangouts.createHangout(owner: owner, invitees: invitees, mode: chosenMode,
                                                                      planDescription: plan, durationsMinutes: durations,
                                                                      durationAny: any)
                creating = false
                router.openHangout(id)
            } catch {
                creating = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Create hangout") {
    NavigationStack {
        CreateHangoutFlowView(uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .environment(TabRouter())
    .preferredColorScheme(.dark)
}
