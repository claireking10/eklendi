import SwiftUI
import Observation

/// A contact picked from iPhone Contacts, matched against Eklendi by phone number.
struct ContactMatch: Identifiable, Hashable {
    let id: String
    let name: String
    let phoneE164: String
    /// Set when the number belongs to an Eklendi user.
    let user: UserProfile?
}

/// Friends list + profile listener (friendIds changes reload the list).
@MainActor
@Observable
final class FriendsModel {
    var me: UserProfile? = nil
    var friends: [UserProfile] = []
    var loaded: Bool = false
    var errorMessage: String? = nil

    @ObservationIgnored private var listener: Cancellable? = nil
    @ObservationIgnored private var lastFriendIds: [String]? = nil
    @ObservationIgnored private var users: UserRepository? = nil
    @ObservationIgnored private var uid: String = ""

    func start(users: UserRepository, uid: String) {
        guard listener == nil else { return }
        self.users = users
        self.uid = uid
        listener = users.observeProfile(uid: uid) { [weak self] profile in
            self?.profileChanged(profile)
        }
    }

    private func profileChanged(_ profile: UserProfile?) {
        me = profile
        let ids: [String] = profile?.friendIds ?? []
        if ids != lastFriendIds {
            lastFriendIds = ids
            reload()
        }
    }

    func reload() {
        guard let users = users else { return }
        let uid: String = self.uid
        Task { @MainActor in
            do {
                let list: [UserProfile] = try await users.friends(of: uid)
                friends = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } catch {
                errorMessage = error.localizedDescription
            }
            loaded = true
        }
    }

    func isFriend(_ uid: String) -> Bool {
        (me?.friendIds ?? []).contains(uid) || friends.contains(where: { $0.id == uid })
    }
}

/// 04a Friends (KAL-13, KAL-14): friends list, add by phone number, add from iPhone Contacts
/// (Add for people on Eklendi, Invite by text for everyone else).
struct FriendsView: View {
    let uid: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(\.openURL) private var openURL: OpenURLAction
    @State private var model: FriendsModel = FriendsModel()

    // Add by phone
    @State private var phoneInput: String = ""
    @State private var isLookingUp: Bool = false
    @State private var addMessage: String? = nil
    @State private var notOnAppPhone: String? = nil

    // Contacts
    @State private var showPicker: Bool = false
    @State private var isMatching: Bool = false
    @State private var matches: [ContactMatch] = []
    @State private var showContactsSheet: Bool = false

    init(uid: String) {
        self.uid = uid
    }

    var body: some View {
        ScreenScaffold(title: "") {
            HStack(alignment: .firstTextBaseline) {
                Text("Friends")
                    .font(EKFont.title)
                    .foregroundStyle(EKColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(model.friends.count == 1 ? "1 friend" : "\(model.friends.count) friends")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .accessibilityIdentifier("friendsCount")
            }
            .padding(.top, 12)

            PrimaryButton("Add from your contacts", systemImage: "person.crop.circle.badge.plus", isLoading: isMatching) {
                showPicker = true
            }
            .accessibilityIdentifier("addFromContactsButton")

            addByPhoneCard

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            friendsList
        }
        .background(
            ContactPickerPresenter(isPresented: $showPicker) { picked in
                match(picked)
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $showContactsSheet) {
            ContactsMatchSheet(uid: uid, matches: matches, model: model)
                .environment(env)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            model.start(users: env.users, uid: uid)
        }
    }

    // MARK: Add by phone

    private var addByPhoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Add by phone number")
            HStack(spacing: 10) {
                EKPhoneField(text: $phoneInput, placeholder: "Friend’s number", accessibilityId: "addFriendPhoneField")
                Button {
                    addByPhone()
                } label: {
                    Group {
                        if isLookingUp {
                            ProgressView().tint(EKColor.onTeal)
                        } else {
                            Text("Add")
                        }
                    }
                    .font(EKFont.button)
                    .foregroundStyle(EKColor.onTeal)
                    .frame(width: 72, height: 56)
                    .background(RoundedRectangle(cornerRadius: EKRadius.button, style: .continuous).fill(EKColor.teal))
                }
                .buttonStyle(.plain)
                .disabled(PhoneFormat.digits(phoneInput).isEmpty || isLookingUp)
                .opacity(PhoneFormat.digits(phoneInput).isEmpty ? 0.4 : 1)
                .accessibilityIdentifier("addFriendButton")
            }
            if let addMessage = addMessage {
                Text(addMessage)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("addFriendMessage")
            }
            if let phone = notOnAppPhone {
                HStack(spacing: 10) {
                    Button {
                        if let url = InviteMessage.smsURL(to: phone) { openURL(url) }
                    } label: {
                        Label("Text an invite", systemImage: "message")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("inviteBySmsButton")

                    ShareLink(item: InviteMessage.text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("shareInviteButton")
                }
            }
        }
    }

    private func addByPhone() {
        addMessage = nil
        notOnAppPhone = nil
        guard let e164 = AccountValidation.normalizePhone(phoneInput) else {
            addMessage = "Enter a 10-digit phone number."
            return
        }
        isLookingUp = true
        Task { @MainActor in
            do {
                if let user = try await env.users.findUser(phoneE164: e164) {
                    if user.id == uid {
                        addMessage = "That’s your own number."
                    } else if model.isFriend(user.id) {
                        addMessage = "\(user.name) is already your friend."
                    } else {
                        try await env.users.addFriend(myUid: uid, friendUid: user.id)
                        addMessage = "Added \(user.name.isEmpty ? PhoneFormat.display(e164) : user.name)."
                        phoneInput = ""
                        model.reload()
                    }
                } else {
                    addMessage = "\(PhoneFormat.display(e164)) isn’t on Eklendi yet. Send them an invite."
                    notOnAppPhone = e164
                }
            } catch {
                addMessage = error.localizedDescription
            }
            isLookingUp = false
        }
    }

    // MARK: Contacts

    private func match(_ picked: [PickedContact]) {
        guard !picked.isEmpty else { return }
        isMatching = true
        Task { @MainActor in
            var out: [ContactMatch] = []
            for contact in picked {
                let numbers: [String] = ContactMatching.normalizedNumbers(contact.phoneNumbers)
                guard let firstNumber = numbers.first else { continue }
                var found: UserProfile? = nil
                var foundNumber: String = firstNumber
                for number in numbers {
                    if let user = try? await env.users.findUser(phoneE164: number) {
                        found = user
                        foundNumber = number
                        break
                    }
                }
                out.append(ContactMatch(id: contact.id, name: contact.name, phoneE164: foundNumber, user: found))
            }
            matches = out
            isMatching = false
            if out.isEmpty {
                model.errorMessage = "Those contacts don’t have a phone number we can use."
            } else {
                showContactsSheet = true
            }
        }
    }

    // MARK: List

    private var friendsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Your friends")
            if !model.loaded {
                ProgressView().tint(EKColor.teal).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if model.friends.isEmpty {
                Card {
                    Text("No friends yet. Add people from your contacts or by phone number to start planning hangouts.")
                        .font(EKFont.callout)
                        .foregroundStyle(EKColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("friendsEmptyState")
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.friends.enumerated()), id: \.element.id) { pair in
                            friendRow(pair.element)
                            if pair.offset < model.friends.count - 1 {
                                Rectangle().fill(EKColor.cardBorder).frame(height: 1).padding(.leading, 70)
                            }
                        }
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: UserProfile) -> some View {
        HStack(spacing: 14) {
            Avatar(name: friend.name.isEmpty ? "?" : friend.name, photoURL: friend.photoURL, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name.isEmpty ? "New friend" : friend.name)
                    .font(EKFont.bodyBold)
                    .foregroundStyle(EKColor.textPrimary)
                Text(PhoneFormat.display(friend.phone))
                    .font(.system(size: 14))
                    .foregroundStyle(EKColor.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("friendRow_\(friend.id)")
    }
}

// MARK: - "Your contacts" sheet

struct ContactsMatchSheet: View {
    let uid: String
    let matches: [ContactMatch]
    let model: FriendsModel

    init(uid: String, matches: [ContactMatch], model: FriendsModel) {
        self.uid = uid
        self.matches = matches
        self.model = model
    }

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss: DismissAction
    @Environment(\.openURL) private var openURL: OpenURLAction
    @State private var added: Set<String> = []
    @State private var adding: Set<String> = []
    @State private var invited: Set<String> = []
    @State private var errorMessage: String? = nil

    private var onApp: [ContactMatch] { matches.filter { $0.user != nil } }
    private var offApp: [ContactMatch] { matches.filter { $0.user == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your contacts")
                    .font(EKFont.title2)
                    .foregroundStyle(EKColor.textPrimary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(EKColor.raised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("contactsSheetClose")
            }
            .padding(.top, 24)

            Text("From your iPhone contacts. Only people you add become friends.")
                .font(EKFont.callout)
                .foregroundStyle(EKColor.muted)
                .padding(.top, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let errorMessage = errorMessage {
                        ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }
                    if !onApp.isEmpty {
                        SectionHeader("On Eklendi").padding(.top, 14)
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(onApp) { m in
                                    row(m) { onAppButton(m) }
                                }
                            }
                        }
                    }
                    if !offApp.isEmpty {
                        SectionHeader("Not on Eklendi yet").padding(.top, 14)
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(offApp) { m in
                                    row(m) { inviteButton(m) }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            PrimaryButton("Done") { dismiss() }
                .accessibilityIdentifier("contactsSheetDone")
                .padding(.bottom, 12)
        }
        .padding(.horizontal, EKSpacing.screen)
        .background(EKColor.sheet.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func row<Trailing: View>(_ m: ContactMatch, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Avatar(name: m.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name)
                    .font(EKFont.bodyBold)
                    .foregroundStyle(EKColor.textPrimary)
                Text(PhoneFormat.display(m.phoneE164))
                    .font(.system(size: 14))
                    .foregroundStyle(EKColor.muted)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func onAppButton(_ m: ContactMatch) -> some View {
        let userId: String = m.user?.id ?? ""
        if userId == uid {
            Text("You").font(EKFont.calloutBold).foregroundStyle(EKColor.muted)
        } else if added.contains(userId) || model.isFriend(userId) {
            smallButton("Added", filled: false) {}
                .disabled(true)
                .accessibilityIdentifier("contactAdded_\(m.id)")
        } else {
            smallButton(adding.contains(userId) ? "Adding…" : "Add", filled: true) {
                add(userId)
            }
            .disabled(adding.contains(userId))
            .accessibilityLabel("Add \(m.name)")
            .accessibilityIdentifier("contactAdd_\(m.id)")
        }
    }

    private func inviteButton(_ m: ContactMatch) -> some View {
        let done: Bool = invited.contains(m.id)
        return Button {
            if let url = InviteMessage.smsURL(to: m.phoneE164) {
                openURL(url)
                invited.insert(m.id)
            }
        } label: {
            Text(done ? "Invited" : "Invite")
                .font(EKFont.calloutBold)
                .foregroundStyle(done ? EKColor.placeholder : EKColor.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(EKColor.raised))
                .overlay(Capsule().stroke(EKColor.raisedBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Text \(m.name) an invite")
        .accessibilityIdentifier("contactInvite_\(m.id)")
    }

    private func smallButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EKFont.calloutBold)
                .foregroundStyle(filled ? EKColor.onTeal : EKColor.teal)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Capsule().fill(filled ? EKColor.teal : Color.clear))
                .overlay(Capsule().stroke(EKColor.teal, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func add(_ friendUid: String) {
        guard !friendUid.isEmpty else { return }
        adding.insert(friendUid)
        Task { @MainActor in
            do {
                try await env.users.addFriend(myUid: uid, friendUid: friendUid)
                added.insert(friendUid)
                model.reload()
            } catch {
                errorMessage = error.localizedDescription
            }
            adding.remove(friendUid)
        }
    }
}

#Preview("Friends") {
    NavigationStack {
        FriendsView(uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .preferredColorScheme(.dark)
}
