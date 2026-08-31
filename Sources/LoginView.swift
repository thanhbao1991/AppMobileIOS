import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var taiKhoan = Prefs.lastTaiKhoan
    @State private var matKhau = "123456"
    @State private var loading = false
    @State private var errorText: String?
    /// Chụp lại 1 lần lúc mở màn hình — tránh đổi giao diện giữa chừng nếu login tự động fail rồi
    /// set errorText (không được nhảy sang chế độ "thủ công" chỉ vì có lỗi, vẫn phải hiện form).
    @State private var manualMode = Prefs.manualLogout

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("ĐENN").font(.system(size: 40, weight: .bold))

            if let errorText {
                Text(errorText).foregroundColor(.red).font(.footnote)
            }

            if manualMode {
                TextField("Tài khoản", text: $taiKhoan)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 32)
                SecureField("Mật khẩu", text: $matKhau)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)

                Button {
                    Task { await doLogin() }
                } label: {
                    if loading {
                        ProgressView()
                    } else {
                        Text("Đăng nhập").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .disabled(loading || taiKhoan.isEmpty || matKhau.isEmpty)
            } else {
                ProgressView()
            }

            Spacer()
        }
        .padding()
        .task {
            if !manualMode {
                await doLogin()
            }
        }
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
