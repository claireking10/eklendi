import SwiftUI

/// Screen 10: who's done with the current step and who's still pending.
/// The owner can nudge or remove pending members (KAL-38, KAL-39).
@MainActor
struct HFWaitingView: View {
    let store: HFHangoutStore
    let uid: String
    let hangoutId: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var removing: HangoutMember? = nil
    @State private var busyIds: Set<String> = []
    @State private var errorMessage: String? = nil

    private var hangout: Hangout? { store.hangout }

    private var rows: [HangoutMember] {
        let group: [HangoutMember] = store.inGroup
        let mine: [HangoutMember] = group.filter { $0.id == uid }
        let others: [HangoutMember] = group.filter { $0.id != uid }
        return mine + others
    }

    private func isDone(_ m: HangoutMember) -> Bool {
        guard let h = hangout else { return false }
        return HFRouting.stepDone(m, hangout: h)
    }

    private var doneCount: Int { rows.filter { isDone($0) }.count }

    private var pendingNames: [String] {
        rows.filter { !isDone($0) }.map { HFFormat.shortName($0, myUid: uid) }
    }

    private var isOwner: Bool { store.isOwner(uid) }

    private var subline: String {
        guard let h = hangout else { return "" }
        let allDone: Bool = pendingNames.isEmpty
        switch h.status {
        case .collectingAvailability:
            return allDone ? "Everyone shared their calendar. Finding times that work…"
                : "We’ll suggest times as soon as everyone has shared when they’re free."
        case .votingTimes:
            return allDone ? "Everyone swiped. Picking the time…"
                : "Your times are in. We’ll pick the time as soon as everyone has swiped."
        case .survey:
            return allDone ? "Everyone answered. Building your ideas…"
                : "Thanks! We’ll build ideas once everyone has answered."
        case .votingCards:
            return allDone ? "Everyone voted. Checking for a match…"
                : "Your votes are in. We’ll show the result as soon as everyone has swiped."
        default:
            return ""
        }
    }

    var body: some View {
        ScreenScaffold(title: HFRouting.waitingHeadline(pendingNames: pendingNames),
                       subtitle: subline,
                       eyebrow: "\(store.displayName(uid: uid)) · \(HFRouting.stepName(hangout?.status ?? .collectingAvailability))") {
            EKProgressBar(progress: rows.isEmpty ? 0 : Double(doneCount) / Double(rows.count),
                          label: "\(doneCount) of \(rows.count)")
            Card(padding: 0, cornerRadius: 20) {
                VStack(spacing: 0) {
                    ForEach(rows) { m in
                        row(m)
                        if m.id != rows.last?.id {
                            Rectangle().fill(EKColor.cardBorder).frame(height: 1)
                        }
                    }
                }
            }
            if isOwner {
                Text("The hangout moves on by itself as soon as everyone’s done. Only you, as the owner, can nudge or remove people.")
                    .font(.system(size: 13))
                    .foregroundStyle(EKColor.placeholder)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let statusMessage = hangout?.statusMessage, !statusMessage.isEmpty {
                HFInfoBanner(statusMessage)
            }
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        }
        .accessibilityIdentifier("waitingView")
        .confirmationDialog("Remove \(removing.map { HFFormat.firstName($0.name) } ?? "them")?",
                            isPresented: removeBinding, titleVisibility: .visible) {
            Button("Remove from hangout", role: .destructive) {
                if let m = removing { remove(m) }
            }
            Button("Keep", role: .cancel) { removing = nil }
        } message: {
            Text("The group keeps planning without them.")
        }
    }

    private var removeBinding: Binding<Bool> {
        Binding<Bool>(get: { removing != nil }, set: { newValue in
            if !newValue { removing = nil }
        })
    }

    private func statusText(_ m: HangoutMember) -> (text: String, color: Color) {
        if isDone(m) {
            switch hangout?.status {
            case .some(.collectingAvailability): return (text: "Shared availability", color: EKColor.teal)
            case .some(.survey): return (text: "Answered", color: EKColor.teal)
            default: return (text: "Done swiping", color: EKColor.teal)
            }
        }
        if m.state == .invited { return (text: "Hasn’t opened it yet", color: EKColor.yellow) }
        if m.nudgedAt != nil { return (text: "Nudged · still going", color: EKColor.yellow) }
        switch hangout?.status {
        case .some(.collectingAvailability): return (text: "Hasn’t shared availability", color: EKColor.yellow)
        case .some(.survey): return (text: "Still answering", color: EKColor.yellow)
        default: return (text: "Still swiping", color: EKColor.yellow)
        }
    }

    private func row(_ m: HangoutMember) -> some View {
        let status: (text: String, color: Color) = statusText(m)
        let pending: Bool = !isDone(m)
        let canManage: Bool = isOwner && pending && m.id != uid
        return HStack(spacing: 12) {
            Avatar(name: m.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.id == uid ? "You" : m.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                Text(status.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(status.color)
            }
            Spacer(minLength: 4)
            if canManage {
                Button {
                    nudge(m)
                } label: {
                    Text(m.nudgedAt == nil ? "Nudge" : "Nudged")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(m.nudgedAt == nil ? Color(hex: "#1A1500") : EKColor.yellow)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(m.nudgedAt == nil ? EKColor.yellow : Color.clear))
                        .overlay(Capsule().stroke(EKColor.yellow, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(busyIds.contains(m.id))
                .accessibilityIdentifier("nudge_\(m.id)")
                Button {
                    removing = m
                } label: {
                    Text("Remove")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(EKColor.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .overlay(Capsule().stroke(EKColor.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(busyIds.contains(m.id))
                .accessibilityIdentifier("remove_\(m.id)")
            } else if !pending {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(EKColor.teal)
            } else {
                ProgressView()
                    .tint(EKColor.yellow)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    private func nudge(_ m: HangoutMember) {
        busyIds.insert(m.id)
        Task { @MainActor in
            do {
                try await env.hangouts.nudge(hangoutId: hangoutId, memberUid: m.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyIds.remove(m.id)
        }
    }

    private func remove(_ m: HangoutMember) {
        removing = nil
        busyIds.insert(m.id)
        Task { @MainActor in
            do {
                try await env.hangouts.remove(hangoutId: hangoutId, memberUid: m.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            busyIds.remove(m.id)
        }
    }
}
