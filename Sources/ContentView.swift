import SwiftUI

/// App native thật (không phải WebView bọc site) — gọi thẳng TraSuaApp.Backend API. 6 tab chính
/// (Hoá đơn/Thanh toán/Công nợ/Chi tiêu/Công việc/Báo cáo) đều nối API thật — chỉ "Tạo hoá đơn"
/// và tab Đenn Signal là chưa làm (bỏ qua theo yêu cầu, để đợt sau).
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
