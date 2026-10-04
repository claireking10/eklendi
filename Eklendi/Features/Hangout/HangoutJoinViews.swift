import SwiftUI

// MARK: - Join (KAL-21)

/// Shown to an invited member: who's in, what's being decided, Join or Decline.
@MainActor
struct HFJoinView: View {
    let store: HFHangoutStore
    let uid: String
    let onDecline: () -> Void

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var joining: Bool = false
    @State private var errorMessage: String? = nil

    private var ownerName: String {
        store.memberName(store.hangout?.ownerId ?? "")
    }

    private var otherMembers: [HangoutMember] {
        store.inGroup.filter { $0.id != uid }
    }

    private var decidingText: String {
        guard let h = store.hangout else { return "" }
        if h.mode == .timeOnly {
            let plan: String = h.planDescription.isEmpty ? "a plan" : "“\(h.planDescription)”"
            return "Just a time for \(plan). You swipe on times that fit your calendar."
        }
        return "A time and something to do. You swipe on times, answer a few quick questions, then vote on ideas."
    }

    private var durationText: String {
        guard let h = store.hangout else { return "" }
        if h.durationAny || h.durationsMinutes.isEmpty { return "Any length" }
        return h.durationsMinutes.sorted().map { HFFormat.durationLabel(minutes: $0) }.joined(separator: ", ")
    }

    var body: some View {
        ScreenScaffold(title: "\(ownerName) invited you",
                       subtitle: "Join to share when you’re free. Your calendar details stay private.",
                       eyebrow: store.displayName(uid: uid)) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Who’s coming")
                    ForEach(otherMembers) { m in
                        HStack(spacing: 12) {
                            Avatar(name: m.name, size: 36)
                            Text(m.name)
                                .font(EKFont.bodyBold)
                            Spacer()
                            if m.role == .owner {
                                Pill("Owner")
                            }
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("What we’re deciding")
                    Text(decidingText)
                        .font(EKFont.callout)
                        .foregroundStyle(EKColor.body)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(EKColor.teal)
                        Text(durationText)
                            .font(EKFont.calloutBold)
                    }
                }
            }
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            VStack(spacing: 6) {
                PrimaryButton("Join", isLoading: joining) { join() }
                    .accessibilityIdentifier("joinHangoutButton")
                Button("Decline hangout", action: onDecline)
                    .buttonStyle(LinkButtonStyle(color: EKColor.dangerText))
                    .accessibilityIdentifier("declineInviteButton")
            }
        }
    }

    private func join() {
        joining = true
        Task { @MainActor in
            do {
                try await env.hangouts.join(hangoutId: store.hangout?.id ?? "", uid: uid)
            } catch {
                errorMessage = error.localizedDescription
            }
            joining = false
        }
    }
}

// MARK: - Starting point + calendar upload (KAL-20, screen "Origin")

/// Time + activity: pick where you'll come from (defaults to home), then the app reads the
/// calendar and uploads busy blocks. Time-only: goes straight to the calendar step.
@MainActor
struct HFAvailabilityView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    private enum Origin { case home, elsewhere }

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var origin: Origin = .home
    @State private var placeText: String = ""
    @State private var working: Bool = false
    @State private var progressText: String = ""
    @State private var errorMessage: String? = nil
    @State private var autoStarted: Bool = false

    private var isTimeOnly: Bool {
        store.hangout?.mode == .timeOnly
    }

    private var homeLocation: Location? {
        store.myProfile?.homeLocation ?? store.me(uid)?.startLocation
    }

    var body: some View {
        if isTimeOnly {
            timeOnlyBody
        } else {
            originBody
        }
    }

    private var timeOnlyBody: some View {
        VStack(spacing: 18) {
            Spacer()
            if working || errorMessage == nil {
                ProgressView()
                    .tint(EKColor.teal)
                    .controlSize(.large)
                Text("Checking your calendar…")
                    .font(EKFont.headline)
                Text("Only busy times are shared, never what’s on your calendar.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .multilineTextAlignment(.center)
            } else if let errorMessage = errorMessage {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(EKColor.yellow)
                Text(errorMessage)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.body)
                    .multilineTextAlignment(.center)
                PrimaryButton("Try again") {
                    Task { @MainActor in await submit() }
                }
                .accessibilityIdentifier("retryAvailabilityButton")
            }
            Spacer()
        }
        .padding(.horizontal, EKSpacing.screen)
        .task {
            guard !autoStarted else { return }
            autoStarted = true
            await submit()
        }
    }

    private var originBody: some View {
        ScreenScaffold(title: "Where will you be coming from?",
                       subtitle: "We’ll favor hangouts that are close to everyone.",
                       eyebrow: "\(store.displayName(uid: uid)) · Before you swipe") {
            VStack(spacing: 12) {
                HFRadioOption(title: "Home",
                              detail: homeLocation?.text ?? "Add your approximate home in Settings",
                              systemImage: "house.fill",
                              isSelected: origin == .home) {
                    origin = .home
                }
                .accessibilityIdentifier("originHome")
                HFRadioOption(title: "Somewhere else",
                              detail: "Work, campus, a friend’s place…",
                              systemImage: "mappin.and.ellipse",
                              isSelected: origin == .elsewhere) {
                    origin = .elsewhere
                }
                .accessibilityIdentifier("originElsewhere")
            }
            if origin == .elsewhere {
                EKTextField("Neighborhood, cross streets or address", text: $placeText,
                            label: "Starting location", systemImage: "mappin",
                            accessibilityId: "startLocationField")
            }
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            VStack(spacing: 10) {
                Text("Only used to pick places. Friends never see it.")
                    .font(EKFont.inter(13))
                    .foregroundStyle(EKColor.muted)
                PrimaryButton(working ? progressText : "Continue to times", isLoading: working) {
                    Task { @MainActor in await submit() }
                }
                .disabled(!canContinue)
                .accessibilityIdentifier("continueToTimesButton")
            }
        }
    }

    private var canContinue: Bool {
        switch origin {
        case .home: return true
        case .elsewhere: return placeText.trimmingCharacters(in: .whitespaces).count >= 3
        }
    }

    @MainActor
    private func submit() async {
        guard !working else { return }
        working = true
        errorMessage = nil
        defer { working = false }
        do {
            if !isTimeOnly {
                var location: Location? = nil
                switch origin {
                case .home:
                    location = homeLocation
                case .elsewhere:
                    progressText = "Finding that place…"
                    location = try await env.functions.geocode(placeText)
                }
                if let location = location {
                    progressText = "Saving…"
                    try await env.hangouts.setStartLocation(hangoutId: hangoutId, uid: uid, location: location)
                }
            }
            progressText = "Checking your calendar…"
            if !env.calendar.isAuthorized {
                let granted: Bool = try await env.calendar.requestAccess()
                if !granted {
                    throw HFError("Eklendi needs calendar access to find when you’re free. Turn it on in Settings › Privacy › Calendars.")
                }
            }
            let now = Date()
            let busy: [BusyBlock] = try await env.calendar.busyBlocks(from: now, to: now.addingTimeInterval(30 * 86_400))
            let buffer: Int = store.myProfile?.bufferMinutes ?? store.me(uid)?.bufferMinutes ?? 15
            progressText = "Sharing busy times…"
            try await env.hangouts.submitAvailability(hangoutId: hangoutId, uid: uid, busy: busy, bufferMinutes: buffer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
