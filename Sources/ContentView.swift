import SwiftUI

/// App native thật (không phải WebView bọc site) — gọi thẳng TraSuaApp.Backend API. 6 tab chính
/// (Hoá đơn/Thanh toán/Công nợ/Chi tiêu/Công việc/Báo cáo) đều nối API thật — chỉ "Tạo hoá đơn"
/// và tab Đenn Signal là chưa làm (bỏ qua theo yêu cầu, để đợt sau).
struct ContentView: View {
    @State private var isLoggedIn = Prefs.isLoggedIn

    var body: some View {
        Group {
            if isLoggedIn {
                MainTabView(isLoggedIn: $isLoggedIn)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .onChange(of: isLoggedIn) { loggedIn in
            if loggedIn {
                Task { await SignalRClient.shared.start { entity, action, id in
                    EntityChangeBus.shared.post(entity, action, id)
                } }
            } else {
                Task { await SignalRClient.shared.stop() }
            }
        }
        .task {
            if isLoggedIn {
                await SignalRClient.shared.start { entity, action, id in
                    EntityChangeBus.shared.post(entity, action, id)
                }
            }
        }
    }
}
