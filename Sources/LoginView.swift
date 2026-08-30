import SwiftUI

struct LoginView: View {
    @Binding var isLoggedIn: Bool
    @State private var matKhau = "123456"
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("ĐENN").font(.system(size: 40, weight: .bold))

            if let errorText {
                Text(errorText).foregroundColor(.red).font(.footnote)
            }

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
            .disabled(loading || matKhau.isEmpty)

            Spacer()
        }
        .padding()
    }

    private func doLogin() async {
        guard !matKhau.isEmpty else {
            errorText = "Nhập mật khẩu."
            return
        }
        loading = true
        errorText = nil
        let result = await APIClient.shared.login(taiKhoan: "admin", matKhau: matKhau)
        loading = false
        switch result {
        case .success(let resp):
            guard let token = resp.token else {
                errorText = "Phản hồi từ server không hợp lệ."
                return
            }
            Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
            isLoggedIn = true
        case .rejected(let message):
            errorText = message
        case .networkError:
            errorText = "Không kết nối được server, thử lại sau."
        }
    }
}
