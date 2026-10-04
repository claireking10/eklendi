import SwiftUI
import Observation
import UIKit

enum OnboardingStep: Hashable {
    case connect, interests
}

/// Answers collected across the onboarding screens.
@MainActor
@Observable
final class OnboardingModel {
    var name: String = ""
    var photo: UIImage? = nil
    var appleCalendarConnected: Bool = false
    var bufferMinutes: Int = BufferSetting.defaultMinutes
    var locationText: String = ""
    var resolvedLocation: Location? = nil
    var interests: String = ""
}

/// Onboarding after sign-up (KAL-8, KAL-9): name + optional photo → 03 calendars, buffer and
/// approximate home → 03a optional interests. Saves the profile with `calendarConnected = true`
/// and calls `env.auth.refresh()` so RootView moves to the main tabs.
struct OnboardingFlowView: View {
    let uid: String

    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @State private var model: OnboardingModel = OnboardingModel()
    @State private var path: [OnboardingStep] = []
    @State private var loaded: Bool = false

    init(uid: String) {
        self.uid = uid
    }

    var body: some View {
        NavigationStack(path: $path) {
            OnboardingNameView(uid: uid, model: model, path: $path)
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .connect:
                        OnboardingConnectView(model: model, path: $path)
                    case .interests:
                        OnboardingInterestsView(uid: uid, model: model)
                    }
                }
        }
        .tint(EKColor.teal)
        .task {
            guard !loaded else { return }
            loaded = true
            model.appleCalendarConnected = env.calendar.isAuthorized
            model.photo = AccountPhotoStore.load(uid: uid)
            if let existing = try? await env.users.profile(uid: uid) {
                if model.name.isEmpty { model.name = existing.name }
                model.bufferMinutes = existing.bufferMinutes
                if let home = existing.homeLocation, model.locationText.isEmpty {
                    model.locationText = home.text
                    model.resolvedLocation = home
                }
                if model.interests.isEmpty { model.interests = existing.interests }
            }
        }
    }
}

// MARK: - Name + photo

struct OnboardingNameView: View {
    let uid: String
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: OnboardingModel
    @Binding var path: [OnboardingStep]

    @State private var errorMessage: String? = nil

    init(uid: String, model: OnboardingModel, path: Binding<[OnboardingStep]>) {
        self.uid = uid
        self.model = model
        self._path = path
    }

    private var trimmed: String { AccountValidation.trimmedName(model.name) }

    var body: some View {
        ScreenScaffold(title: "What should friends call you?",
                       subtitle: "This is how you’ll show up in hangouts. Add a photo if you like.") {
            VStack(alignment: .leading, spacing: EKSpacing.lg) {
                HStack {
                    Spacer()
                    ProfilePhotoPickerButton(uid: uid, name: trimmed, image: $model.photo, size: 96)
                    Spacer()
                }
                EKTextField("Your name", text: $model.name, accessibilityId: "nameField")
                if let errorMessage = errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                }
            }
        } footer: {
            VStack(spacing: 4) {
                PrimaryButton("Continue") {
                    guard !trimmed.isEmpty else {
                        errorMessage = "Add your name so friends know it’s you."
                        return
                    }
                    errorMessage = nil
                    path.append(.connect)
                }
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("nameContinueButton")

                Button("Not you? Log out") {
                    try? env.auth.signOut()
                }
                .buttonStyle(LinkButtonStyle(color: EKColor.muted))
                .accessibilityIdentifier("onboardingSignOutButton")
            }
        }
    }
}

// MARK: - 03 Calendars, buffer, home location

struct OnboardingConnectView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: OnboardingModel
    @Binding var path: [OnboardingStep]

    init(model: OnboardingModel, path: Binding<[OnboardingStep]>) {
        self.model = model
        self._path = path
    }

    @State private var isConnecting: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var locationError: String? = nil
    @State private var showGoogleNote: Bool = false

    var body: some View {
        ScreenScaffold(title: "Let’s see when you’re free",
                       subtitle: "We only read busy and free times, never event names or details.",
                       showsBack: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Calendars")
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        AccountCalendarRow(name: "Apple Calendar",
                                           isConnected: model.appleCalendarConnected,
                                           isBusy: isConnecting,
                                           accessibilityId: "appleCalendarToggle") {
                            toggleApple()
                        }
                        .padding(.horizontal, 16)
                        Rectangle().fill(EKColor.cardBorder).frame(height: 1)
                        AccountCalendarRow(name: "Google Calendar",
                                           isConnected: false,
                                           isComingSoon: true,
                                           accessibilityId: "googleCalendarToggle") {}
                            .padding(.horizontal, 16)
                    }
                }
                Text("Connect at least one calendar to finish signing up.")
                    .font(EKFont.callout)
                    .foregroundStyle(model.appleCalendarConnected ? EKColor.muted : EKColor.yellow)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Buffer around events")
                AccountBufferStepper(minutes: $model.bufferMinutes)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader("Where you live, roughly")
                    Text("Never shown to friends")
                        .font(EKFont.inter(12, .semibold))
                        .foregroundStyle(EKColor.muted)
                        .fixedSize()
                }
                AccountHomeLocationField(text: $model.locationText, error: locationError)
                    .onChange(of: model.locationText) { _, _ in
                        locationError = nil
                        model.resolvedLocation = nil
                    }
            }

            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            PrimaryButton("Continue", isLoading: isSaving) {
                continueTapped()
            }
            .accessibilityIdentifier("connectContinueButton")
        }
    }

    private func toggleApple() {
        if model.appleCalendarConnected {
            // Can't revoke system access from the app; just mark it as not used.
            model.appleCalendarConnected = false
            return
        }
        isConnecting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let granted: Bool = try await env.calendar.requestAccess()
                model.appleCalendarConnected = granted
                if !granted {
                    errorMessage = "Calendar access is off. Turn it on in the Settings app under Privacy & Security → Calendars."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func continueTapped() {
        guard model.appleCalendarConnected else {
            errorMessage = "Connect at least one calendar to continue."
            return
        }
        if let problem = HomeLocationValidation.error(model.locationText) {
            locationError = problem
            return
        }
        errorMessage = nil
        let text: String = model.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved = model.resolvedLocation, resolved.text == text {
            path.append(.interests)
            return
        }
        isSaving = true
        Task { @MainActor in
            do {
                let loc: Location = try await env.functions.geocode(text)
                model.resolvedLocation = Location(text: text, lat: loc.lat, lng: loc.lng)
            } catch {
                // Keep going with the typed text; the backend can geocode later.
                model.resolvedLocation = Location(text: text, lat: 0, lng: 0)
            }
            isSaving = false
            path.append(.interests)
        }
    }
}

// MARK: - 03a Interests (optional)

struct OnboardingInterestsView: View {
    let uid: String
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: OnboardingModel

    init(uid: String, model: OnboardingModel) {
        self.uid = uid
        self.model = model
    }

    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var hasText: Bool {
        !model.interests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScreenScaffold(title: "What kinds of hangouts are you into?",
                       subtitle: "Write it however you like. We’ll lean toward these, and still mix in new ideas.",
                       eyebrow: "Optional",
                       showsBack: true) {
            AccountInterestsEditor(text: $model.interests)
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
        } footer: {
            VStack(spacing: 6) {
                Text("You can change this anytime in Settings.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                PrimaryButton(hasText ? "Save and continue" : "Continue", isLoading: isSaving) {
                    finish(skip: false)
                }
                .accessibilityIdentifier("interestsSaveButton")
                Button("Skip for now") {
                    finish(skip: true)
                }
                .buttonStyle(LinkButtonStyle(color: EKColor.muted))
                .disabled(isSaving)
                .accessibilityIdentifier("interestsSkipButton")
            }
        }
    }

    private func finish(skip: Bool) {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                // Re-read so phone / friendIds / createdAt written at sign-up are kept.
                let existing: UserProfile? = try? await env.users.profile(uid: uid)
                var profile: UserProfile = existing ?? UserProfile(id: uid, phone: "", name: "")
                profile.id = uid
                profile.name = AccountValidation.trimmedName(model.name)
                profile.bufferMinutes = model.bufferMinutes
                let text: String = model.locationText.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.homeLocation = model.resolvedLocation ?? Location(text: text, lat: 0, lng: 0)
                profile.interests = skip ? "" : model.interests.trimmingCharacters(in: .whitespacesAndNewlines)
                profile.calendarConnected = true
                try await env.users.saveProfile(profile)
                await env.auth.refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview("Onboarding") {
    OnboardingFlowView(uid: "u_new")
        .environment(AppEnvironment.mock)
        .preferredColorScheme(.dark)
}
