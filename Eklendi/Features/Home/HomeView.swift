import SwiftUI
import Observation

/// Live list of the user's hangouts plus each hangout's members (for "your turn" and avatars).
@MainActor
@Observable
final class HomeModel {
    var hangouts: [Hangout] = []
    var members: [String: [HangoutMember]] = [:]
    var loaded: Bool = false

    @ObservationIgnored private var listListener: Cancellable? = nil
    @ObservationIgnored private var memberListeners: [String: Cancellable] = [:]
    @ObservationIgnored private var started: Bool = false

    func start(repo: HangoutRepository, uid: String) {
        guard !started else { return }
        started = true
        listListener = repo.observeMyHangouts(uid: uid) { [weak self] list in
            self?.apply(list, repo: repo)
        }
    }

    private func apply(_ list: [Hangout], repo: HangoutRepository) {
        hangouts = list
        loaded = true
        let ids: Set<String> = Set(list.map { $0.id })
        for id in ids where memberListeners[id] == nil {
            memberListeners[id] = repo.observeMembers(hangoutId: id) { [weak self] ms in
                self?.members[id] = ms
            }
        }
        let stale: [String] = memberListeners.keys.filter { !ids.contains($0) }
        for id in stale {
            memberListeners[id]?.cancel()
            memberListeners[id] = nil
            members[id] = nil
        }
    }
}

/// 04 Home (KAL-10): date + tagline, "Needs your swipes", "In progress", "Coming up",
/// Plan a hangout. Header icons jump to the Friends / Settings tabs.
struct HomeView: View {
    let uid: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(TabRouter.self) private var router: TabRouter
    @State private var model: HomeModel = HomeModel()

    init(uid: String) {
        self.uid = uid
    }

    private struct Entry: Identifiable {
        let hangout: Hangout
        let info: HomeTileInfo
        let title: String
        let others: [String]
        let going: Int
        var id: String { hangout.id }
    }

    private var entries: [Entry] {
        model.hangouts.map { h in
            let ms: [HangoutMember] = model.members[h.id] ?? []
            let me: HangoutMember? = ms.first(where: { $0.id == uid })
            let ownerName: String? = ms.first(where: { $0.id == h.ownerId })?.name
                ?? ms.first(where: { $0.role == .owner })?.name
            let others: [String] = ms
                .filter { $0.id != uid && ($0.state == .active || $0.state == .invited) }
                .map { $0.name.isEmpty ? "Friend" : $0.name }
            return Entry(hangout: h,
                         info: HomeSectioning.info(for: h, me: me, myUid: uid, ownerName: ownerName),
                         title: HomeSectioning.title(for: h, myUid: uid, ownerName: ownerName),
                         others: others,
                         going: HomeSectioning.goingCount(ms))
        }
    }

    private func entries(in section: HomeSection, from all: [Entry]) -> [Entry] {
        let inSection: [Entry] = all.filter { $0.info.section == section }
        let order: [Hangout] = HomeSectioning.sorted(inSection.map { $0.hangout }, in: section)
        return order.compactMap { h in inSection.first(where: { $0.id == h.id }) }
    }

    var body: some View {
        let all: [Entry] = entries
        let visible: [Entry] = all.filter { $0.info.section != .hidden }
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(AccountFormat.longDay(Date()))
                        .padding(.top, 20)
                    Text("Make time for the people that matter most.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    if !model.loaded {
                        ProgressView()
                            .tint(EKColor.teal)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else if visible.isEmpty {
                        emptyState.padding(.top, 28)
                    } else {
                        ForEach([HomeSection.needsAction, .inProgress, .upcoming, .past], id: \.self) { section in
                            let list: [Entry] = entries(in: section, from: all)
                            if !list.isEmpty {
                                SectionHeader(section.title, color: sectionColor(section))
                                    .padding(.top, 28)
                                    .accessibilityIdentifier("homeSection_\(section.rawValue)")
                                VStack(spacing: 10) {
                                    ForEach(list) { entry in
                                        row(entry)
                                    }
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                }
                .padding(.horizontal, EKSpacing.screen)
                .padding(.bottom, EKSpacing.lg)
            }
            // Hangouts scroll behind the button; it stays put on every screen size.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingFooter {
                    NavigationLink(value: CreateHangoutRoute()) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                            Text("Plan a hangout")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("createHangoutButton")
                }
            }
        }
        .ekScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            model.start(repo: env.hangouts, uid: uid)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            iconButton(systemImage: "person.2", label: "Friends", id: "homeFriendsButton") {
                router.select(.friends)
            }
            Spacer()
            Text("eklendi")
                .font(EKFont.wordmark)
                .tracking(-1.2)
                .foregroundStyle(EKColor.textPrimary)
            Spacer()
            iconButton(systemImage: "gearshape", label: "Settings", id: "homeSettingsButton") {
                router.select(.settings)
            }
        }
        .padding(.horizontal, EKSpacing.screen - 6)
        .padding(.top, 8)
    }

    private func iconButton(systemImage: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(EKColor.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func sectionColor(_ section: HomeSection) -> Color {
        switch section {
        case .needsAction: return EKColor.yellow
        case .past: return EKColor.muted
        default: return EKColor.teal
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: Entry) -> some View {
        NavigationLink(value: HangoutRoute(hangoutId: entry.id)) {
            switch entry.info.section {
            case .upcoming, .past:
                confirmedTile(entry)
            default:
                planningTile(entry)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hangoutRow_\(entry.id)")
    }

    private func planningTile(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(entry.title)
                    .font(EKFont.headline)
                    .foregroundStyle(EKColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                AvatarStack(names: entry.others, size: 34, ringColor: EKColor.card, maxVisible: 4)
            }
            HStack(spacing: 10) {
                Text(entry.info.status)
                    .font(.system(size: 15))
                    .foregroundStyle(EKColor.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let action = entry.info.action {
                    HStack(spacing: 4) {
                        Text(action)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    }
                    .font(EKFont.calloutBold)
                    .foregroundStyle(EKColor.teal)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(EKColor.placeholder)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous).fill(EKColor.card))
        .overlay(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous))
    }

    private func confirmedTile(_ entry: Entry) -> some View {
        let isPast: Bool = entry.info.section == .past
        let start: Date? = HomeSectioning.startDate(entry.hangout)
        let end: Date? = entry.hangout.confirmed?.end ?? entry.hangout.winningSlot?.end
        var detail: String = ""
        if let start = start, let end = end {
            detail = AccountFormat.timeRange(start, end)
        }
        let goingText: String = "\(entry.going) going"
        if entry.info.status == "You’re not going" {
            detail = detail.isEmpty ? entry.info.status : detail + " · " + entry.info.status
        } else if !isPast {
            detail = detail.isEmpty ? goingText : detail + " · " + goingText
        }
        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(start.map { AccountFormat.weekdayShort($0) } ?? "—")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                Text(start.map { AccountFormat.dayNumber($0) } ?? "")
                    .font(.system(size: 24, weight: .heavy))
            }
            .foregroundStyle(isPast ? EKColor.textPrimary : EKColor.onTeal)
            .frame(width: 56, height: 60)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isPast ? EKColor.raised : EKColor.teal))

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(EKColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(EKColor.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(EKColor.placeholder)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous).fill(EKColor.card))
        .overlay(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous).stroke(EKColor.cardBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: EKRadius.card, style: .continuous))
        .opacity(isPast ? 0.75 : 1)
    }

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(EKColor.teal)
                Text("No hangouts yet")
                    .font(EKFont.headline)
                    .foregroundStyle(EKColor.textPrimary)
                Text("Plan one and we’ll find a time that works for everyone, then suggest places to go.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("homeEmptyState")
    }
}

#Preview("Home") {
    NavigationStack {
        HomeView(uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .environment(TabRouter())
    .preferredColorScheme(.dark)
}
