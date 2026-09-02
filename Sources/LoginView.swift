import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var taiKhoan = Prefs.lastTaiKhoan
    @State private var matKhau = "123456"
    @State private var showMatKhau = false
    @State private var loading = false
    @State private var errorText: String?
    @FocusState private var focusedField: Field?
    /// Chụp lại 1 lần lúc mở màn hình — tránh đổi giao diện giữa chừng nếu login tự động fail rồi
    /// set errorText (không được nhảy sang chế độ "thủ công" chỉ vì có lỗi, vẫn phải hiện form).
    @State private var manualMode = Prefs.manualLogout

    private enum Field { case taiKhoan, matKhau }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            // ScrollView (thay vì VStack trần) để SwiftUI tự tránh bàn phím - VStack đứng riêng
            // trong ZStack KHÔNG được hệ thống tự đẩy lên khi bàn phím hiện.
            ScrollView {
                VStack(spacing: 28) {
                    logoHeader

                    if let errorText {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(errorText)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if manualMode {
                        manualForm
                    } else {
                        VStack(spacing: 14) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Đang đăng nhập...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(28)
                .frame(maxWidth: 400)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if !manualMode {
                await doLogin()
            }
        }
    }

    private var logoHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: 76, height: 76)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            .shadow(color: Color.brandPrimary.opacity(0.35), radius: 10, y: 6)

            Text("ĐENN")
                .font(.system(size: 34, weight: .bold))
                .tracking(4)
            Text("Quản lý bán hàng")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var manualForm: some View {
        VStack(spacing: 16) {
            fieldContainer(icon: "person.fill") {
                TextField("Tài khoản", text: $taiKhoan)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: .taiKhoan)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .matKhau }
            }

            fieldContainer(icon: "lock.fill") {
                Group {
                    if showMatKhau {
                        TextField("Mật khẩu", text: $matKhau)
                    } else {
                        SecureField("Mật khẩu", text: $matKhau)
                    }
                }
                .focused($focusedField, equals: .matKhau)
                .submitLabel(.go)
                .onSubmit { Task { await doLogin() } }

                Button {
                    showMatKhau.toggle()
                } label: {
                    Image(systemName: showMatKhau ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task { await doLogin() }
            } label: {
                ZStack {
                    if loading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Đăng nhập")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .foregroundColor(.white)
            .background(
                (taiKhoan.isEmpty || matKhau.isEmpty || loading) ? Color.brandPrimary.opacity(0.35) : Color.brandPrimary,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .disabled(loading || taiKhoan.isEmpty || matKhau.isEmpty)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 1)
        )
    }

    private func doLogin() async {
        guard !taiKhoan.isEmpty, !matKhau.isEmpty else {
            errorText = "Nhập tài khoản và mật khẩu."
            return
        }
        loading = true
        errorText = nil
        let result = await APIClient.shared.login(taiKhoan: taiKhoan, matKhau: matKhau)
        loading = false
        switch result {
        case .success(let resp):
            guard let token = resp.token else {
                errorText = "Phản hồi từ server không hợp lệ."
                return
            }
            Prefs.lastTaiKhoan = taiKhoan
            Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
            isLoggedIn = true
        case .rejected(let message):
            errorText = message
            // Auto-login thất bại (vd server đổi mật khẩu mặc định) — chuyển sang form thủ công
            // thay vì đứng yên với 1 spinner vô nghĩa không ai bấm được gì.
            if !manualMode { manualMode = true }
        case .networkError:
            errorText = "Không kết nối được server, thử lại sau."
            if !manualMode { manualMode = true }
        }
    }
}
