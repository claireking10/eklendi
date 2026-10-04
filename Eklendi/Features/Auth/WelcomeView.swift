import SwiftUI
import Observation

/// Sign-up steps pushed from the Welcome (log in) screen.
enum SignUpStep: Hashable {
    case phone, code, password
}

/// State shared by the three sign-up screens (02 Phone → code → password).
@MainActor
@Observable
final class SignUpModel {
    var phoneInput: String = ""
    var phoneE164: String = ""
    var verificationId: String = ""
    var code: String = ""
    var password: String = ""
}

/// 01 Welcome (KAL-7): log in with phone number + password, or start sign-up.
/// Phone number is the username. No email, no Google/Apple sign-in (CLAUDE.md "Accounts").
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment

    @State private var path: [SignUpStep] = []
    @State private var signUp: SignUpModel = SignUpModel()
    @State private var phone: String = ""
    @State private var password: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    init() {}

    var body: some View {
        NavigationStack(path: $path) {
            loginScreen
                .navigationDestination(for: SignUpStep.self) { step in
                    switch step {
                    case .phone:
                        SignUpPhoneView(model: signUp, path: $path)
                    case .code:
                        SignUpCodeView(model: signUp, path: $path)
                    case .password:
                        SignUpPasswordView(model: signUp, path: $path)
                    }
                }
        }
        .tint(EKColor.teal)
    }

    private var canSubmit: Bool {
        !PhoneFormat.digits(phone).isEmpty && !password.isEmpty && !isLoading
    }

    private var loginScreen: some View {
        ScreenScaffold(title: "") {
            VStack(alignment: .leading, spacing: 0) {
                Text("eklendi")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .tracking(-1.4)
                    .foregroundStyle(EKColor.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .accessibilityIdentifier("welcomeWordmark")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Glad to see you again.")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(EKColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Log in to your account.")
                        .font(.system(size: 16))
                        .foregroundStyle(EKColor.muted)
                }
                .padding(.top, 56)

                VStack(spacing: 12) {
                    EKPhoneField(text: $phone, placeholder: "Phone number", accessibilityId: "loginPhoneField")
                    EKTextField("Password", text: $password, kind: .secure, systemImage: "lock",
                                accessibilityId: "loginPasswordField")
                    if let errorMessage = errorMessage {
                        ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }
                    PrimaryButton("Log in", isLoading: isLoading) {
                        logIn()
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("loginButton")
                    .padding(.top, 8)
                }
                .padding(.top, 32)
            }
        } footer: {
            HStack(spacing: 4) {
                Text("Don’t have an account?")
                    .font(.system(size: 15))
                    .foregroundStyle(EKColor.muted)
                Button("Sign up") {
                    errorMessage = nil
                    path.append(.phone)
                }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("signUpLink")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func logIn() {
        guard let e164 = AccountValidation.normalizePhone(phone) else {
            errorMessage = "Enter your 10-digit phone number."
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Enter your password."
            return
        }
        errorMessage = nil
        isLoading = true
        Task { @MainActor in
            do {
                try await env.auth.signIn(phoneE164: e164, password: password)
                // RootView switches screens when env.auth.state changes.
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - 02 Phone number

struct SignUpPhoneView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: SignUpModel
    @Binding var path: [SignUpStep]

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScreenScaffold(title: "Enter your phone number",
                       subtitle: "Friends find you by your number. We’ll text a code to confirm it.",
                       showsBack: true) {
            VStack(alignment: .leading, spacing: 12) {
                EKPhoneField(text: $model.phoneInput, accessibilityId: "signUpPhoneField")
                Text("Your phone number is your username. US numbers only for now.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                if let errorMessage = errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                }
            }
        } footer: {
            PrimaryButton("Next", isLoading: isLoading) {
                sendCode()
            }
            .disabled(PhoneFormat.digits(model.phoneInput).isEmpty || isLoading)
            .accessibilityIdentifier("phoneNextButton")
        }
    }

    private func sendCode() {
        guard let e164 = AccountValidation.normalizePhone(model.phoneInput) else {
            errorMessage = "Enter a 10-digit US phone number."
            return
        }
        errorMessage = nil
        isLoading = true
        Task { @MainActor in
            do {
                let verificationId: String = try await env.auth.sendCode(to: e164)
                model.phoneE164 = e164
                model.verificationId = verificationId
                model.code = ""
                path.append(.code)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - SMS code

struct SignUpCodeView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: SignUpModel
    @Binding var path: [SignUpStep]

    @State private var isResending: Bool = false
    @State private var errorMessage: String? = nil
    @State private var info: String? = nil

    var body: some View {
        ScreenScaffold(title: "Enter the code",
                       subtitle: "We texted a 6-digit code to \(PhoneFormat.display(model.phoneE164)).",
                       showsBack: true) {
            VStack(alignment: .leading, spacing: 12) {
                EKTextField("6-digit code", text: $model.code, kind: .code, accessibilityId: "codeField")
                    .onChange(of: model.code) { _, newValue in
                        let cleaned: String = AccountValidation.cleanCode(newValue)
                        if cleaned != newValue { model.code = cleaned }
                    }
                HStack(spacing: 4) {
                    Text("Didn’t get it?")
                        .font(.system(size: 15))
                        .foregroundStyle(EKColor.muted)
                    Button(isResending ? "Sending…" : "Resend code") {
                        resend()
                    }
                    .buttonStyle(LinkButtonStyle())
                    .disabled(isResending)
                    .accessibilityIdentifier("resendCodeButton")
                }
                if let info = info {
                    Text(info).font(EKFont.callout).foregroundStyle(EKColor.teal)
                }
                if let errorMessage = errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                }
            }
        } footer: {
            PrimaryButton("Next") {
                guard AccountValidation.isValidCode(model.code) else {
                    errorMessage = "Enter the 6-digit code we texted you."
                    return
                }
                errorMessage = nil
                path.append(.password)
            }
            .disabled(!AccountValidation.isValidCode(model.code))
            .accessibilityIdentifier("codeNextButton")
        }
    }

    private func resend() {
        isResending = true
        info = nil
        Task { @MainActor in
            do {
                model.verificationId = try await env.auth.sendCode(to: model.phoneE164)
                info = "New code sent."
            } catch {
                errorMessage = error.localizedDescription
            }
            isResending = false
        }
    }
}

// MARK: - Create password

struct SignUpPasswordView: View {
    @Environment(AppEnvironment.self) private var env: AppEnvironment
    @Bindable var model: SignUpModel
    @Binding var path: [SignUpStep]

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ScreenScaffold(title: "Create a password",
                       subtitle: "Next time, log in with your phone number and this password.",
                       showsBack: true) {
            VStack(alignment: .leading, spacing: 12) {
                EKTextField("Password", text: $model.password, kind: .secure, systemImage: "lock",
                            accessibilityId: "newPasswordField")
                Text("At least \(AccountValidation.minPasswordLength) characters.")
                    .font(EKFont.callout)
                    .foregroundStyle(EKColor.muted)
                if let errorMessage = errorMessage {
                    ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    Button("Re-enter the code") {
                        if !path.isEmpty { path.removeLast() }
                    }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("reenterCodeButton")
                }
            }
        } footer: {
            PrimaryButton("Create account", isLoading: isLoading) {
                createAccount()
            }
            .disabled(model.password.isEmpty || isLoading)
            .accessibilityIdentifier("createAccountButton")
        }
    }

    private func createAccount() {
        if let problem = AccountValidation.passwordError(model.password) {
            errorMessage = problem
            return
        }
        errorMessage = nil
        isLoading = true
        Task { @MainActor in
            do {
                try await env.auth.verifyAndCreateAccount(verificationId: model.verificationId,
                                                          code: model.code,
                                                          phoneE164: model.phoneE164,
                                                          password: model.password)
                // State becomes .needsOnboarding → RootView shows OnboardingFlowView.
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AppEnvironment.mock)
        .preferredColorScheme(.dark)
}
