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
        ZStack(alignment: .top) {
            Group {
                if isLoggedIn {
                    MainTabView(isLoggedIn: $isLoggedIn)
                } else {
                    LoginView(isLoggedIn: $isLoggedIn)
                }
            }
            // Hiện lý do vừa rung (xem EntityChangeBus.toastText) — đặt ở gốc ContentView để hiện đè
            // lên MỌI tab, không riêng tab đang xem. KHÔNG ignoresSafeArea (khác trước đây) — để banner
            // tự nằm trong safe area giống DaySearchBar/SearchBar, cùng gốc toạ độ nên căn đúng vị trí
            // ô tìm kiếm mà không cần hardcode offset theo tai thỏ/Dynamic Island từng máy.
            SignalToastBanner()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sessionExpired)) { _ in
            isLoggedIn = false
        }
        .onChange(of: isLoggedIn) { loggedIn in
            if loggedIn {
                Task { await SignalRClient.shared.start { entity, action, id, voice in
                    EntityChangeBus.shared.post(entity, action, id, voice: voice)
                } }
                DesktopScreenStore.shared.start()
            } else {
                Task { await SignalRClient.shared.stop() }
                DesktopScreenStore.shared.stop()
            }
        }
        // Đổi app qua lại (background→foreground) khiến kết nối SignalR chết âm thầm — không kick
        // ngay thì phải chờ backoff (3-30s) tự retry mới nối lại (tab Xem màn hình Desktop giờ
        // không còn phụ thuộc SignalR nữa — HTTP polling thuần — nhưng EntityChanged/tin nhắn vẫn
        // qua kênh này nên vẫn cần kick sớm).
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                // Không có UIBackgroundModes nào khai báo → iOS suspend app gần như ngay khi vào nền,
                // socket WebSocket chết theo. beginBackgroundTask xin thêm ~30s thực thi (mức Apple
                // cấp cho tác vụ thường, không cần entitlement) — đủ để việc đổi app NHANH (xem tin
                // nhắn rồi quay lại ngay, không phải rời hẳn nhiều phút) không làm rớt kết nối, khỏi
                // phải chờ backoff tự retry mới nhận lại EntityChanged/tin nhắn.
                backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "signalr-keep-alive") {
                    UIApplication.shared.endBackgroundTask(backgroundTaskId)
                    backgroundTaskId = .invalid
                }
                // Poll màn hình Desktop dừng luôn lúc vào nền — không có ý nghĩa gì khi user không
                // nhìn thấy màn hình (khác SignalR, không cần giữ "sống" qua background).
                DesktopScreenStore.shared.stop()
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
                    DesktopScreenStore.shared.start()
                }
            }
        }
        .task {
            if isLoggedIn {
                await SignalRClient.shared.start { entity, action, id, voice in
                    EntityChangeBus.shared.post(entity, action, id, voice: voice)
                }
                DesktopScreenStore.shared.start()
            }
        }
    }
}

/// Banner ngắn hiện lý do rung, tự tắt sau vài giây (EntityChangeBus xoá toastText). Không chặn
/// thao tác — đặt lên trên cùng, cho phép chạm xuyên qua phần trống còn lại của màn hình.
private struct SignalToastBanner: View {
    @ObservedObject private var bus = EntityChangeBus.shared
    /// Theo ngón tay khi vuốt lên để tắt SỚM banner đang hiện — chỉ ảnh hưởng banner này, tin nhắn
    /// tiếp theo (EntityChangeBus.post) vẫn hiện bình thường qua toastText mới.
    @State private var dragOffset: CGFloat = 0

    /// warningColor (vàng amber) quá sáng để chữ trắng đọc được — riêng nó dùng chữ đen, các màu
    /// còn lại (xanh/đỏ/hồng/xám) đủ tối cho chữ trắng.
    private var fgColor: Color { bus.toastColor == .warningColor ? .black : .white }

    var body: some View {
        if let text = bus.toastText {
            // Gói gọn 1 dòng (nhãn: nội dung) thay vì 2 dòng riêng — để chiều cao khớp đúng
            // ô tìm kiếm (SearchFieldRow: padding dọc 7 quanh 1 dòng chữ ≈ 36pt), tràn thì cắt "...".
            HStack(spacing: 6) {
                Image(systemName: bus.toastIcon)
                    .font(.system(size: 14))
                Text(text.isEmpty ? bus.toastLabel : "\(bus.toastLabel): \(text)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundColor(fgColor)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(bus.toastColor, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            // padding(.top, 8) + padding(.horizontal, 16) khớp CHÍNH XÁC padding ngoài của
            // DaySearchBar (.padding(.horizontal) mặc định = 16, .padding(.vertical, 8)) — cùng
            // gốc safe area (không ignoresSafeArea nữa) nên banner chồng khít lên đúng vị trí ô
            // tìm kiếm, không lệch xuống dưới hay tràn lên trên như trước.
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .offset(y: dragOffset)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: bus.toastText)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Chỉ theo chiều vuốt LÊN — vuốt xuống không kéo giãn banner ra khỏi vị trí.
                        dragOffset = min(0, value.translation.height)
                    }
                    .onEnded { value in
                        if value.translation.height < -20 {
                            bus.dismissToast()
                        }
                        dragOffset = 0
                    }
            )
            // Trước đây false để chạm xuyên qua banner xuống nội dung bên dưới — giờ cần bắt được
            // gesture vuốt nên phải nhận hit-test, chấp nhận đánh đổi: lúc banner hiện (~3.5s),
            // vùng nó che tạm thời chặn tap xuống nội dung ngay dưới.
        }
    }
}
