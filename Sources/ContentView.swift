import SwiftUI
import UIKit

/// App native thật (không phải WebView bọc site) — gọi thẳng TraSuaApp.Backend API. 6 tab chính
/// (Hoá đơn/Thanh toán/Công nợ/Chi tiêu/Công việc/Báo cáo) đều nối API thật — chỉ "Tạo hoá đơn"
/// và tab Đenn Signal là chưa làm (bỏ qua theo yêu cầu, để đợt sau).
struct ContentView: View {
    @State private var isLoggedIn = Prefs.isLoggedIn
    @Environment(\.scenePhase) private var scenePhase
    @State private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

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
            if newPhase == .background {
                // Không có UIBackgroundModes nào khai báo → iOS suspend app gần như ngay khi vào nền,
                // socket WebSocket chết theo. beginBackgroundTask xin thêm ~30s thực thi (mức Apple
                // cấp cho tác vụ thường, không cần entitlement) — đủ để việc đổi app NHANH (xem tin
                // nhắn rồi quay lại ngay, không phải rời hẳn nhiều phút) không làm rớt kết nối, khỏi
                // phải chờ StartWatchingDesktop nối lại từ đầu ở tab Xem màn hình Desktop.
                backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "signalr-keep-alive") {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
            } else if newPhase == .active {
                if backgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
                // CHỈ kickReconnect khi kết nối THẬT SỰ đã chết — beginBackgroundTask ở trên xin
                // ~30s thực thi nền, kết nối THƯỜNG vẫn còn sống suốt thời gian đó (đổi app nhanh
                // rồi quay lại ngay). Trước đây ép reconnect VÔ ĐIỀU KIỆN mỗi lần quay lại foreground
                // — dù kết nối vẫn còn sống, vẫn bị phá đi tạo lại, đúng cảm giác "mất kết nối liền"
                // user báo dù có beginBackgroundTask.
                if isLoggedIn {
                    Task {
                        if await !SignalRClient.shared.isConnected {
                            await SignalRClient.shared.kickReconnect()
                        }
                    }
                }
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
