import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`.
/// (2026-08-26: quay lại kiến trúc JPEG push đơn giản này sau khi thử VP9 video thật — nhiều lần
/// sửa vẫn không ổn định phía iOS (video đứng hình, gesture bắn lặp) — quay về đúng bản đã verify
/// hoạt động thật với chạm tay thật.) Vào màn hình gọi `StartWatchingDesktop` 1 lần, Desktop tự
/// chụp+gửi 1 khung JPEG FULL-FRAME mỗi 100ms qua `ScreenshotReceived` (không dirty-rect — đơn giản,
/// dễ đoán, đủ dùng cho nhu cầu "xem app đang chạy gì") tới khi rời màn hình gọi `StopWatchingDesktop`.
/// 1 watchdog tự gọi lại `StartWatchingDesktop` nếu lâu không có khung hình mới (mạng rớt/reconnect).
/// READ-ONLY thuần — bỏ hẳn click (2026-08-26, sau nhiều lần vẫn không chính xác dù đã verify
/// Desktop+Backend hoàn toàn ổn — không đáng công sức tiếp tục dò lệch toạ độ). Desktop chỉ chụp
/// đúng vùng `HoaDonGrid` (tab Hoá đơn, xem `SignalRClient.cs` phía Desktop) chứ không phải toàn màn
/// hình — ảnh nhận về hiển thị NGUYÊN TỈ LỆ, vừa khít chiều ngang điện thoại (`.scaledToFit`, không
/// crop/pan/zoom gì cả) để khỏi méo hình, hở viền đen trên/dưới nếu tỉ lệ khác nhau. Nút X góc trên
/// để thoát.
struct DesktopScreenView: View {
    let desktopId: String
    let label: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentDesktopId: String = ""
    @State private var image: UIImage?
    @State private var disconnected = false
    @State private var isReconnecting = false
    @State private var watchdogTask: Task<Void, Never>?
    @State private var lastFrameAt: Date = .distantPast

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if disconnected {
                // Không phân biệt được "mất kết nối thật" với "Desktop đang mở tab khác, không chụp
                // được HoaDonGrid" (cả 2 đều biểu hiện giống nhau: không có khung hình mới) — dùng
                // chung 1 thông báo bao quát cả 2 khả năng, tránh nói sai "đã ngắt kết nối" khi thực
                // ra vẫn đang kết nối tốt, chỉ là Desktop chưa mở đúng tab (verify thực tế 2026-08-26).
                VStack(spacing: 8) {
                    Text("\(label): chưa nhận được hình")
                        .foregroundStyle(.white)
                    Text("Kiểm tra Desktop có đang mở tab Hoá đơn không, hoặc có bị mất kết nối không")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }

            // App bị hạ xuống nền một lúc rồi mở lại trong lúc vẫn ở màn hình này — poll/kết nối
            // SignalR đã treo/rớt trong lúc đó, ảnh cũ vẫn còn hiện nên cần báo rõ đang nối lại,
            // tránh người dùng tưởng app bị đơ.
            if isReconnecting {
                VStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Đang kết nối lại...")
                        .foregroundStyle(.white)
                }
                .padding(20)
                .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .statusBarHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            currentDesktopId = desktopId
            startWatching()
        }
        .onDisappear {
            watchdogTask?.cancel()
            let target = currentDesktopId
            Task {
                _ = try? await SignalRClient.shared.invoke("StopWatchingDesktop", args: [target])
                await SignalRClient.shared.setScreenshotHandler(nil)
            }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                isReconnecting = true
                Task { _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId]) }
            }
        }
    }

    private func startWatching() {
        Task {
            await SignalRClient.shared.setScreenshotHandler { data, x, y, w, h in
                applyFrame(data, x: x, y: y, w: w, h: h)
            }
            _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])
        }

        // Desktop tự đẩy khung hình MỖI 100ms KHÔNG ĐIỀU KIỆN khi tab Hoá đơn đang mở (không còn
        // dirty-rect/skip-khi-đứng-yên như bản trước) — nên "lâu không thấy gì" giờ là tín hiệu đáng
        // tin cậy hơn nhiều (bất kể lý do: mất kết nối THẬT, hoặc Desktop đang mở tab khác không
        // chụp được HoaDonGrid — cả 2 đều hợp lệ dừng gửi khung hình). Ngưỡng rút ngắn nhiều so với
        // bản dirty-rect cũ (không cần chờ ~30s nữa, verify thực tế 2026-08-26 user báo chờ quá lâu).
        watchdogTask = Task {
            var staleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }

                let stale = Date().timeIntervalSince(lastFrameAt) > 1
                if !stale { staleTicks = 0; continue }

                staleTicks += 1
                _ = await tryResolveNewId()
                _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])

                // ~5s không có khung hình mới nào — báo ngay, không bắt người dùng chờ ~30s như bản
                // dirty-rect cũ (giờ mỗi khung hình chỉ cách nhau 100ms khi mọi thứ bình thường).
                if staleTicks >= 5 { disconnected = true }
            }
        }
    }

    /// Vẽ đè khung hình mới (có thể chỉ là 1 dải dirty-rect) lên canvas đang hiển thị. Khung hình
    /// đầu tiên (chưa có canvas) hoặc khung "chữa lành" định kỳ (kích thước khác canvas hiện có)
    /// coi như thay hẳn canvas; còn lại vẽ patch đúng vị trí (x, y) lên canvas cũ.
    @MainActor
    private func applyFrame(_ data: Data, x: Int, y: Int, w: Int, h: Int) {
        guard let patch = UIImage(data: data) else { return }
        let isFullReplace = x == 0 && y == 0
            && (image == nil || CGSize(width: w, height: h) != image!.size)
        if isFullReplace {
            image = patch
        } else if let canvas = image {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: canvas.size, format: format)
            image = renderer.image { _ in
                canvas.draw(at: .zero)
                patch.draw(at: CGPoint(x: x, y: y))
            }
        }
        lastFrameAt = Date()
        disconnected = false
        isReconnecting = false
    }

    private func tryResolveNewId() async -> Bool {
        guard let desktops = try? await SignalRClient.shared.fetchConnectedDesktops(),
              let match = desktops.first(where: { $0.value == label }),
              match.key != currentDesktopId else { return false }
        currentDesktopId = match.key
        return true
    }
}
