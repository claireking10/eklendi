import SwiftUI

/// One hangout, start to finish. Observes the hangout, its members, slots and cards and
/// shows the right screen for `hangout.status` and my own progress (see HFRouting).
/// Pushed for `HangoutRoute` on the Home tab.
@MainActor
struct HangoutFlowView: View {
    let hangoutId: String
    let uid: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss: DismissAction
    @State private var store: HFHangoutStore = HFHangoutStore()
    @State private var errorMessage: String? = nil
    @State private var showDecline: Bool = false
    @State private var declining: Bool = false
    @State private var showCancelConfirm: Bool = false
    @State private var showReopenConfirm: Bool = false
    @State private var showHandOff: Bool = false

    init(hangoutId: String, uid: String) {
        self.hangoutId = hangoutId
        self.uid = uid
    }

    private var screen: HFScreen {
        HFRouting.screen(hangout: store.hangout, me: store.me(uid), membersLoaded: store.membersLoaded)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ekScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .foregroundStyle(EKColor.textPrimary)
        .errorBanner($errorMessage)
        .task {
            store.start(env: env, hangoutId: hangoutId)
            await store.loadProfile(env: env, uid: uid)
        }
        .onChange(of: store.hangout?.status) { _, _ in
            cleanUpCalendarIfNeeded()
        }
        .sheet(isPresented: $showDecline) {
            HFDeclineSheet(hangoutName: store.displayName(uid: uid),
                           ownerFirstName: store.memberName(store.hangout?.ownerId ?? ""),
                           isWorking: declining,
                           onKeep: { showDecline = false },
                           onDecline: { decline() })
        }
        .sheet(isPresented: $showHandOff) {
            HFHandOffSheet(candidates: store.participants.filter { $0.id != uid },
                           onPick: { member in handOff(to: member) },
                           onCancel: { showHandOff = false })
        }
        .confirmationDialog("Cancel this hangout?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Cancel hangout", role: .destructive) { cancelHangout() }
            Button("Keep planning", role: .cancel) {}
        } message: {
            Text("Everyone is told, and the event comes off calendars.")
        }
        .confirmationDialog("Reopen planning?", isPresented: $showReopenConfirm, titleVisibility: .visible) {
            Button("Reopen") { reopen() }
            Button("Keep the plan", role: .cancel) {}
        } message: {
            Text("The group picks a time again and everyone retakes the activity questions.")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            BackButton()
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, EKSpacing.screen - 4)
    }

    @ViewBuilder
    private var trailing: some View {
        if let h = store.hangout, h.status != .cancelled, let me = store.me(uid) {
            if h.ownerId == uid {
                Menu {
                    if h.status == .confirmed {
                        Button {
                            showReopenConfirm = true
                        } label: {
                            Label("Reopen planning", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Button {
                        showHandOff = true
                    } label: {
                        Label("Hand off ownership", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    Button(role: .destructive) {
                        showCancelConfirm = true
                    } label: {
                        Label("Cancel hangout", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(EKColor.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Owner options")
                .accessibilityIdentifier("ownerMenu")
            } else if me.state == .active && h.status != .confirmed {
                Button("Decline hangout") { showDecline = true }
                    .buttonStyle(LinkButtonStyle(color: EKColor.dangerText))
                    .accessibilityIdentifier("declineHangoutButton")
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .loading:
            LoadingView()
        case .notMember:
            HFStatusView(systemImage: "person.crop.circle.badge.xmark",
                         title: "You’re not in this hangout",
                         message: "You declined or were removed, so the group is planning without you.")
        case .join:
            HFJoinView(store: store, uid: uid, onDecline: { showDecline = true })
        case .availability:
            HFAvailabilityView(store: store, uid: uid, hangoutId: hangoutId)
        case .waiting:
            HFWaitingView(store: store, uid: uid, hangoutId: hangoutId)
        case .swipeTimes:
            HFSwipeTimesView(store: store, uid: uid, hangoutId: hangoutId)
        case .noMutualTime:
            HFNoTimesView(store: store, uid: uid, hangoutId: hangoutId,
                          onCancelHangout: { showCancelConfirm = true })
        case .survey:
            HFSurveyView(store: store, uid: uid, hangoutId: hangoutId)
        case .generating:
            HFStatusView(systemImage: "sparkles", title: "Finding ideas…",
                         message: "Matching everyone’s answers with real places near the group.",
                         showsSpinner: true)
                .accessibilityIdentifier("generatingView")
        case .cards:
            HFCardsView(store: store, uid: uid, hangoutId: hangoutId)
                .id("cards-\(store.hangout?.round ?? 0)")
        case .noAgreement:
            HFNoAgreementView(store: store, uid: uid, hangoutId: hangoutId)
                .id("noAgreement-\(store.hangout?.round ?? 0)")
        case .confirmed:
            HFMatchView(store: store, uid: uid, hangoutId: hangoutId)
        case .cancelled:
            HFStatusView(systemImage: "xmark.circle",
                         title: "This hangout was cancelled",
                         message: cancelledMessage)
                .accessibilityIdentifier("cancelledView")
        }
    }

    private var cancelledMessage: String {
        let msg: String = store.hangout?.statusMessage ?? ""
        return msg.isEmpty ? "The owner called it off. Nothing else to do here." : msg
    }

    // MARK: Actions

    private func decline() {
        declining = true
        Task {
            do {
                try await env.hangouts.decline(hangoutId: hangoutId, uid: uid)
                declining = false
                showDecline = false
                dismiss()
            } catch {
                declining = false
                showDecline = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancelHangout() {
        Task {
            do {
                try await env.hangouts.cancel(hangoutId: hangoutId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reopen() {
        Task {
            do {
                try await env.hangouts.reopen(hangoutId: hangoutId)
                HFLocalStore.clearVotedSlotIds(hangoutId: hangoutId, uid: uid)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handOff(to member: HangoutMember) {
        showHandOff = false
        Task {
            do {
                try await env.hangouts.handOff(hangoutId: hangoutId, toUid: member.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The event we added to my calendar comes off again when the hangout is cancelled or
    /// reopened (CLAUDE.md: cancel removes calendar events).
    private func cleanUpCalendarIfNeeded() {
        guard let status = store.hangout?.status, status != .confirmed,
              let record = HFLocalStore.calendarEvent(hangoutId: hangoutId) else { return }
        HFLocalStore.clearCalendarEvent(hangoutId: hangoutId)
        let calendar: CalendarServicing = env.calendar
        Task {
            try? await calendar.removeEvent(identifier: record.identifier)
        }
    }
}

#Preview("Voting times") {
    NavigationStack {
        HangoutFlowView(hangoutId: MockStore.Ids.votingTimes, uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .environment(TabRouter())
    .preferredColorScheme(.dark)
}

#Preview("Confirmed") {
    NavigationStack {
        HangoutFlowView(hangoutId: MockStore.Ids.confirmed, uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .environment(TabRouter())
    .preferredColorScheme(.dark)
}

#Preview("Invited") {
    NavigationStack {
        HangoutFlowView(hangoutId: MockStore.Ids.collecting, uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .environment(TabRouter())
    .preferredColorScheme(.dark)
}
