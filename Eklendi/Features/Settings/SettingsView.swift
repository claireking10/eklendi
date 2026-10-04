import SwiftUI
import Observation
import UIKit

/// Live profile for Settings.
@MainActor
@Observable
final class SettingsModel {
    var profile: UserProfile? = nil
    @ObservationIgnored private var listener: Cancellable? = nil

    func start(users: UserRepository, uid: String) {
        guard listener == nil else { return }
        listener = users.observeProfile(uid: uid) { [weak self] p in
            self?.profile = p
        }
    }
}

/// 04b Settings (KAL-15, KAL-16): name + photo, approximate home location, interests, buffer,
/// calendar status, sign out, delete account (with confirmation).
struct SettingsView: View {
    let uid: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var model: SettingsModel = SettingsModel()

    // Drafts
    @State private var didLoad: Bool = false
    @State private var name: String = ""
    @State private var locationText: String = ""
    @State private var interests: String = ""
    @State private var bufferMinutes: Int = BufferSetting.defaultMinutes
    @State private var photo: UIImage? = nil

    @State private var isSaving: Bool = false
    @State private var savedNote: String? = nil
    @State private var errorMessage: String? = nil
    @State private var locationError: String? = nil

    @State private var calendarConnected: Bool = false
    @State private var isConnectingCalendar: Bool = false
    @State private var calendarNote: String? = nil

    @State private var confirmingDelete: Bool = false
    @State private var isDeleting: Bool = false

    init(uid: String) {
        self.uid = uid
    }

    private var original: UserProfile? { model.profile }

    private var isDirty: Bool {
        guard let p = original else { return false }
        return AccountValidation.trimmedName(name) != p.name
            || locationText.trimmingCharacters(in: .whitespacesAndNewlines) != (p.homeLocation?.text ?? "")
            || interests.trimmingCharacters(in: .whitespacesAndNewlines) != p.interests
            || bufferMinutes != p.bufferMinutes
    }

    var body: some View {
        ScreenScaffold(title: "Settings") {
            if original == nil && !didLoad {
                ProgressView().tint(EKColor.teal).frame(maxWidth: .infinity).padding(.top, 40)
            } else {
                profileSection
                locationSection
                interestsSection
                bufferSection
                saveSection
                calendarSection
                accountSection
            }
        }
        .errorBanner($errorMessage)
        .onAppear {
            model.start(users: env.users, uid: uid)
            calendarConnected = env.calendar.isAuthorized
            if photo == nil { photo = AccountPhotoStore.load(uid: uid) }
            loadDrafts()
        }
        .onChange(of: model.profile) { _, _ in
            loadDrafts()
        }
    }

    private func loadDrafts() {
        guard let p = model.profile else { return }
        // Don't clobber edits in progress.
        if didLoad && isDirty { return }
        name = p.name
        locationText = p.homeLocation?.text ?? ""
        interests = p.interests
        bufferMinutes = p.bufferMinutes
        didLoad = true
    }

    // MARK: Sections

    private var profileSection: some View {
        HStack(spacing: 16) {
            ProfilePhotoPickerButton(uid: uid, name: AccountValidation.trimmedName(name), image: $photo, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                EKTextField("Your name", text: $name, accessibilityId: "settingsNameField")
                if let phone = original?.phone, !phone.isEmpty {
                    Text(PhoneFormat.display(phone))
                        .font(EKFont.inter(14))
                        .foregroundStyle(EKColor.muted)
                        .padding(.leading, 4)
                        .accessibilityIdentifier("settingsPhone")
                }
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Home location")
            AccountHomeLocationField(text: $locationText, error: locationError, accessibilityId: "settingsLocationField")
                .onChange(of: locationText) { _, _ in locationError = nil }
        }
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Hangouts you’re into")
            AccountInterestsEditor(text: $interests, accessibilityId: "settingsInterestsField")
        }
    }

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Buffer around events")
            AccountBufferStepper(minutes: $bufferMinutes)
        }
    }

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            PrimaryButton("Save changes", isLoading: isSaving) {
                save()
            }
            .disabled(!isDirty || isSaving)
            .accessibilityIdentifier("settingsSaveButton")
            if let savedNote = savedNote {
                Text(savedNote)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.teal)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("settingsSavedNote")
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Calendars")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    AccountCalendarRow(name: "Apple Calendar",
                                       isConnected: calendarConnected,
                                       isBusy: isConnectingCalendar,
                                       accessibilityId: "settingsAppleCalendarToggle") {
                        toggleCalendar()
                    }
                    .padding(.horizontal, 16)
                    Rectangle().fill(EKColor.cardBorder).frame(height: 1)
                    AccountCalendarRow(name: "Google Calendar",
                                       isConnected: false,
                                       isComingSoon: true,
                                       accessibilityId: "settingsGoogleCalendarToggle") {}
                        .padding(.horizontal, 16)
                }
            }
            if let calendarNote = calendarNote {
                Text(calendarNote)
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Account")
            SecondaryButton("Log out", systemImage: "rectangle.portrait.and.arrow.right") {
                do {
                    try env.auth.signOut()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .accessibilityIdentifier("signOutButton")

            if confirmingDelete {
                Card(borderColor: EKColor.danger.opacity(0.6)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Delete your account?")
                            .font(EKFont.headline)
                            .foregroundStyle(EKColor.textPrimary)
                        Text("Your profile, friends and hangout history will be removed. This can’t be undone.")
                            .font(EKFont.callout)
                            .foregroundStyle(EKColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("Cancel") { confirmingDelete = false }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(isDeleting)
                                .accessibilityIdentifier("cancelDeleteButton")
                            Button {
                                deleteAccount()
                            } label: {
                                if isDeleting {
                                    ProgressView().tint(Color.white)
                                } else {
                                    Text("Delete")
                                }
                            }
                            .buttonStyle(DestructiveButtonStyle())
                            .disabled(isDeleting)
                            .accessibilityIdentifier("confirmDeleteButton")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("deleteConfirmation")
            } else {
                Button("Delete account") { confirmingDelete = true }
                    .buttonStyle(DestructiveButtonStyle())
                    .accessibilityIdentifier("deleteAccountButton")
            }
        }
        .padding(.top, 8)
    }

    // MARK: Actions

    private func save() {
        guard let base = original else { return }
        let trimmedName: String = AccountValidation.trimmedName(name)
        guard !trimmedName.isEmpty else {
            errorMessage = "Your name can’t be empty."
            return
        }
        let text: String = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationChanged: Bool = text != (base.homeLocation?.text ?? "")
        if locationChanged, let problem = HomeLocationValidation.error(text) {
            locationError = problem
            return
        }
        errorMessage = nil
        savedNote = nil
        isSaving = true
        Task { @MainActor in
            var updated: UserProfile = base
            updated.id = uid
            updated.name = trimmedName
            updated.interests = interests.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.bufferMinutes = bufferMinutes
            if locationChanged {
                do {
                    let loc: Location = try await env.functions.geocode(text)
                    updated.homeLocation = Location(text: text, lat: loc.lat, lng: loc.lng)
                } catch {
                    updated.homeLocation = Location(text: text, lat: 0, lng: 0)
                }
            }
            do {
                try await env.users.saveProfile(updated)
                savedNote = "Saved."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func toggleCalendar() {
        if calendarConnected {
            calendarNote = "To disconnect, turn off calendar access for Eklendi in the Settings app. At least one calendar is needed to plan hangouts."
            return
        }
        isConnectingCalendar = true
        calendarNote = nil
        Task { @MainActor in
            do {
                let granted: Bool = try await env.calendar.requestAccess()
                calendarConnected = granted
                if !granted {
                    calendarNote = "Calendar access is off. Turn it on in the Settings app under Privacy & Security → Calendars."
                } else if var p = original, !p.calendarConnected {
                    p.calendarConnected = true
                    try? await env.users.saveProfile(p)
                }
            } catch {
                calendarNote = error.localizedDescription
            }
            isConnectingCalendar = false
        }
    }

    private func deleteAccount() {
        isDeleting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await env.auth.deleteAccount()
                AccountPhotoStore.remove(uid: uid)
                // RootView returns to Welcome when the auth state becomes .signedOut.
            } catch {
                errorMessage = error.localizedDescription
                confirmingDelete = false
            }
            isDeleting = false
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView(uid: MockStore.Ids.zach)
    }
    .environment(AppEnvironment.mock)
    .preferredColorScheme(.dark)
}
