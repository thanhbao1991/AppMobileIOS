import SwiftUI

/// App native thật (không phải WebView bọc site) — gọi thẳng TraSuaApp.Backend API, port từ
/// AppMobileAndroid. Chỉ tab "Hoá đơn" có nội dung đầy đủ, các tab khác là vỏ (theo yêu cầu).
struct ContentView: View {
    @State private var isLoggedIn = Prefs.isLoggedIn

    var body: some View {
        if isLoggedIn {
            MainTabView(isLoggedIn: $isLoggedIn)
        } else {
            LoginView(isLoggedIn: $isLoggedIn)
        }
    }
}
