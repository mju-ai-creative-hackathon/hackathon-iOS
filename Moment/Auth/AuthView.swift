import SwiftUI

/// 이메일 로그인 / 회원가입 (Backend /api/auth/login, /api/auth/signup)
struct AuthView: View {
    enum Mode { case login, signup }
    @Environment(AuthSession.self) private var auth
    @State private var mode: Mode = .login

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var showPassword = false

    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var errorMessage: String?
    @State private var fieldErrors: [String: String] = [:]
    @FocusState private var focus: Field?
    enum Field { case name, email, password, confirm }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 48)

                VStack(spacing: 14) {
                    if mode == .signup {
                        field("이름", text: $name, key: "name", icon: "person", field: .name)
                            .textContentType(.name)
                            .submitLabel(.next)
                    }
                    field("이메일", text: $email, key: "email", icon: "envelope", field: .email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                    secureField("비밀번호" + (mode == .signup ? " (8자 이상)" : ""), text: $password,
                                key: "password", field: .password)
                    if mode == .signup {
                        secureField("비밀번호 확인", text: $passwordConfirm, key: "passwordConfirm", field: .confirm)
                    }
                }
                .padding(.top, 36)
                .onSubmit(next)

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(errorMessage)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.red)
                    .padding(.top, 14)
                    .transition(.opacity)
                }

                Button(action: submit) {
                    ZStack {
                        if isLoading { ProgressView().tint(.white) }
                        else { Text(mode == .login ? "로그인" : "가입하고 시작하기") }
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmit ? Theme.red : Theme.red.opacity(0.35)))
                }
                .disabled(!canSubmit || isLoading)
                .padding(.top, 24)

                HStack(spacing: 10) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text("또는").font(.system(size: 12)).foregroundStyle(Theme.gray)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .padding(.top, 22)

                Button(action: google) {
                    HStack(spacing: 10) {
                        if isGoogleLoading { ProgressView() } else {
                            Text("G").font(.system(size: 18, weight: .heavy))
                                .foregroundStyle(LinearGradient(colors: [.blue, .red, .yellow, .green],
                                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        Text("Google로 계속하기").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
                .disabled(isLoading || isGoogleLoading)
                .padding(.top, 14)

                HStack(spacing: 4) {
                    Text(mode == .login ? "아직 계정이 없나요?" : "이미 계정이 있나요?")
                        .foregroundStyle(Theme.gray)
                    Button(mode == .login ? "회원가입" : "로그인") { switchMode() }
                        .fontWeight(.bold).foregroundStyle(Theme.red)
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Button("로그인 없이 둘러보기") { auth.continueAsGuest() }
                    .font(.system(size: 13)).foregroundStyle(Theme.gray).underline()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: mode)
        .animation(.snappy(duration: 0.2), value: errorMessage)
    }

    // MARK: 헤더
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandLogo(size: 30)
            Text(mode == .login ? "다시 만나서 반가워요!\n서울의 순간을 이어서 담아볼까요?"
                                : "설로그에 오신 걸 환영해요.\n이메일로 간단히 가입해 보세요.")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                .lineSpacing(3)
        }
    }

    // MARK: 입력 필드
    private func field(_ placeholder: String, text: Binding<String>, key: String, icon: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(Theme.gray).frame(width: 20)
                TextField(placeholder, text: text).focused($focus, equals: field)
            }
            .modifier(FieldBox(focused: focus == field, error: fieldErrors[key] != nil))
            fieldError(key)
        }
    }

    private func secureField(_ placeholder: String, text: Binding<String>, key: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "lock").foregroundStyle(Theme.gray).frame(width: 20)
                Group {
                    if showPassword { TextField(placeholder, text: text) }
                    else { SecureField(placeholder, text: text) }
                }
                .textContentType(mode == .signup ? .newPassword : .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: field)
                .submitLabel(isLastField(field) ? .go : .next)
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(Theme.gray)
                }
            }
            .modifier(FieldBox(focused: focus == field, error: fieldErrors[key] != nil))
            fieldError(key)
        }
    }

    @ViewBuilder private func fieldError(_ key: String) -> some View {
        if let msg = fieldErrors[key] {
            Text(msg).font(.system(size: 12)).foregroundStyle(Theme.red).padding(.leading, 4)
        }
    }

    // MARK: 검증 (백엔드 SignupRequest / LoginRequest 규칙과 동일)
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool {
        mode == .login ? (!trimmedEmail.isEmpty && !password.isEmpty)
                       : (!name.trimmingCharacters(in: .whitespaces).isEmpty && !trimmedEmail.isEmpty
                          && !password.isEmpty && !passwordConfirm.isEmpty)
    }

    private func validate() -> [String: String] {
        var e: [String: String] = [:]
        if trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            e["email"] = "올바른 이메일 형식이어야 합니다."
        }
        if mode == .signup {
            let n = name.trimmingCharacters(in: .whitespaces)
            if n.isEmpty { e["name"] = "이름은 필수입니다." }
            else if n.count > 100 { e["name"] = "이름은 100자 이하여야 합니다." }
            if password.count < 8 || password.count > 72 { e["password"] = "비밀번호는 8자 이상 72자 이하여야 합니다." }
            if password != passwordConfirm { e["passwordConfirm"] = "비밀번호가 일치하지 않아요." }
        }
        return e
    }

    // MARK: 액션
    private func isLastField(_ f: Field) -> Bool { mode == .login ? f == .password : f == .confirm }

    private func next() {
        switch focus {
        case .name: focus = .email
        case .email: focus = .password
        case .password: if mode == .signup { focus = .confirm } else { submit() }
        case .confirm, .none: submit()
        }
    }

    private func switchMode() {
        mode = mode == .login ? .signup : .login
        errorMessage = nil; fieldErrors = [:]; password = ""; passwordConfirm = ""
    }

    private func google() {
        errorMessage = nil; fieldErrors = [:]
        isGoogleLoading = true
        Task {
            defer { isGoogleLoading = false }
            do { try await auth.signInWithGoogle() }
            catch { errorMessage = (error as? LocalizedError)?.errorDescription ?? "구글 로그인에 실패했어요." }
        }
    }

    private func submit() {
        guard canSubmit, !isLoading else { return }
        errorMessage = nil
        fieldErrors = validate()
        guard fieldErrors.isEmpty else { return }
        focus = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                if mode == .login {
                    try await auth.login(email: trimmedEmail, password: password)
                } else {
                    try await auth.signup(email: trimmedEmail, name: name.trimmingCharacters(in: .whitespaces),
                                          password: password)
                }
            } catch let e as APIError {
                fieldErrors = e.fieldErrors
                errorMessage = e.fieldErrors.isEmpty ? e.errorDescription : nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct FieldBox: ViewModifier {
    let focused: Bool
    let error: Bool
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .padding(.horizontal, 14).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(error ? Theme.red : (focused ? Theme.ink.opacity(0.6) : Theme.line), lineWidth: 1))
    }
}
