import SwiftUI

/// App native thật (không phải WebView bọc site) — gọi thẳng TraSuaApp.Backend API. 6 tab chính
/// (Hoá đơn/Thanh toán/Công nợ/Chi tiêu/Công việc/Báo cáo) đều nối API thật — chỉ "Tạo hoá đơn"
/// và tab Đenn Signal là chưa làm (bỏ qua theo yêu cầu, để đợt sau).
struct ContentView: View {
    @State private var isLoggedIn = Prefs.isLoggedIn
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if isLoggedIn {
                MainTabView(isLoggedIn: $isLoggedIn)
            } else {
                LoginView(isLoggedIn: $isLoggedIn)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            isLoggedIn = false
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
        // Đổi app qua lại (background→foreground) khiến kết nối SignalR chết âm thầm — không kick
        // ngay thì phải chờ backoff (3-30s) tự retry mới nối lại, trong lúc đó MỌI invoke() (kể cả
        // tap-to-click ở tab Xem màn hình Desktop) fail âm thầm (dùng try?), trông như "không hoạt
        // động" dù chỉ đang chờ reconnect.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active, isLoggedIn {
                Task { await SignalRClient.shared.kickReconnect() }
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
