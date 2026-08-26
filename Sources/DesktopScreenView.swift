import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy `targetLabel` cố định (2026-08-26: bỏ hẳn
/// bước chọn máy — trước đây cho chọn giữa nhiều máy đang mở app, nhưng thực tế chỉ cần xem đúng 1
/// máy POS thật (`DESKTOP-118TMVD`) nên vào thẳng, không cần dải chọn máy nữa). Chỉ mở từ icon cạnh
/// nút "+" ở tab Hoá đơn (`HoaDonListView`, dạng sheet giống form thêm hoá đơn) — đã bỏ khỏi menu
/// chung (`MainTabView`). Vào watch gọi `StartWatchingDesktop`
/// 1 lần, Desktop tự chụp+gửi 1 khung JPEG FULL-FRAME mỗi 100ms qua `ScreenshotReceived` (không
/// dirty-rect) tới khi rời màn hình gọi `StopWatchingDesktop`. 1 watchdog tự gọi lại
/// `StartWatchingDesktop` nếu lâu không có khung hình mới (mạng rớt/reconnect).
/// READ-ONLY thuần — bỏ hẳn click (2026-08-26, sau nhiều lần vẫn không chính xác dù đã verify
/// Desktop+Backend hoàn toàn ổn — không đáng công sức tiếp tục dò lệch toạ độ). Desktop chỉ chụp
/// đúng vùng `HoaDonGrid` (control luôn Visibility=Visible + RenderTargetBitmap, xem
/// `SignalRClient.cs`/`DashboardWindow.xaml` phía Desktop) chứ không phải toàn màn hình — GỬI ĐƯỢC
/// DÙ Desktop đang xem tab khác, không riêng lúc tab Hoá đơn đang mở. Ảnh nhận về hiển thị NGUYÊN
/// TỈ LỆ (`.scaledToFit`, không crop/pan/zoom) để khỏi méo hình.
struct DesktopScreenView: View {
    /// Tên máy cố định — đúng máy POS thật đang chạy Desktop client (xem memory
    /// `feedback_138_kill_no_ask`), không còn cho chọn máy khác nữa.
    private let targetLabel = "DESKTOP-118TMVD"

    @State private var selectedDesktopId: String?
    @State private var notFound = false
    @State private var image: UIImage?
    @State private var disconnected = false
    @State private var isReconnecting = false
    @State private var watchdogTask: Task<Void, Never>?
    @State private var lastFrameAt: Date = .distantPast

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// Chiều cao sheet tính THẲNG từ chiều rộng màn hình (không đo động qua GeometryReader/PreferenceKey
    /// nữa — bản trước dùng cách đó nhưng `presentationDetents` lại bị đặt bên trong nội dung của
    /// `NavigationStack` do `HoaDonListView` bọc `NavigationStack { DesktopScreenView() }` từ bên ngoài,
    /// khiến SwiftUI không áp dụng detent đúng (sheet co về gần kích thước tối thiểu). Giờ
    /// `DesktopScreenView` tự bọc `NavigationStack` và đặt `presentationDetents` NGOÀI nó — đúng cấp
    /// theo yêu cầu của SwiftUI.
    private let navBarHeightEstimate: CGFloat = 44
    private var contentHeight: CGFloat { screenWidth / screenAspectRatio }

    var body: some View {
        NavigationStack {
            screenArea
                .background(Color(.systemBackground))
                .navigationTitle("Xem màn hình Desktop")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { dismiss() }
                    }
                }
                .task { await connect() }
                .onDisappear { stopWatching() }
                .onChange(of: scenePhase) { newPhase in
                    guard let id = selectedDesktopId, newPhase == .active else { return }
                    isReconnecting = true
                    Task { _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [id]) }
                }
        }
        .presentationDetents([.height(contentHeight + navBarHeightEstimate)])
        .presentationDragIndicator(.visible)
    }

    /// Khung đen chỉ cao vừa đúng theo tỉ lệ ảnh nhận được (Desktop chụp `HoaDonGrid` — thường lùn,
    /// rộng hơn nhiều so với màn hình dọc điện thoại) — trước đây ép `maxHeight: .infinity` khiến
    /// khung cao gần hết màn hình trong khi ảnh chỉ chiếm 1 dải mỏng ở giữa do `scaledToFit`, để lộ
    /// viền đen thừa rất nhiều phía trên/dưới.
    // Chiều cao tính THẲNG theo chiều rộng màn hình (cố định, không phụ thuộc layout của sheet) —
    // trước đây dùng .aspectRatio(fit) + .frame(maxWidth: .infinity) khiến chiều cao của khung này
    // và chiều cao đo được của sheet (qua GeometryReader ở `body`) phụ thuộc vòng tròn lẫn nhau,
    // SwiftUI xử lý bằng cách co khung này về gần 0 (chỉ còn navbar+picker strip hiện ra được).
    @ViewBuilder
    private var screenArea: some View {
        ZStack {
            Color.black

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if notFound {
                Text("\(targetLabel) chưa mở app")
                    .foregroundStyle(.white.opacity(0.7))
            } else if disconnected {
                Text("\(targetLabel) đã ngắt kết nối")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
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
        .frame(width: screenWidth, height: screenWidth / screenAspectRatio)
    }

    private var screenWidth: CGFloat { UIScreen.main.bounds.width }

    private var screenAspectRatio: CGFloat {
        guard let image, image.size.height > 0 else { return 16.0 / 9.0 }
        return image.size.width / image.size.height
    }

    private func connect() async {
        guard let desktops = try? await SignalRClient.shared.fetchConnectedDesktops(),
              let match = desktops.first(where: { $0.value == targetLabel }) else {
            notFound = true
            return
        }
        notFound = false
        selectedDesktopId = match.key
        startWatching()
    }

    private func startWatching() {
        guard let id = selectedDesktopId else { return }
        Task {
            await SignalRClient.shared.setScreenshotHandler { data, x, y, w, h in
                applyFrame(data, x: x, y: y, w: w, h: h)
            }
            _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [id])
        }

        // Desktop tự đẩy khung hình MỖI 100ms KHÔNG ĐIỀU KIỆN (HoaDonGrid luôn render — xem
        // SignalRClient.cs phía Desktop — nên gửi được bất kể đang xem tab nào trên Desktop), không
        // còn dirty-rect/skip-khi-đứng-yên như bản trước — "lâu không thấy gì" giờ là tín hiệu mất
        // kết nối đáng tin cậy, ngưỡng rút ngắn nhiều so với bản dirty-rect cũ.
        watchdogTask = Task {
            var staleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let id = selectedDesktopId else { return }

                let stale = Date().timeIntervalSince(lastFrameAt) > 1
                if !stale { staleTicks = 0; continue }

                staleTicks += 1
                _ = await tryResolveNewId()
                _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [selectedDesktopId ?? id])

                // ~5s không có khung hình mới nào — báo ngay, không bắt người dùng chờ ~30s như bản
                // dirty-rect cũ (giờ mỗi khung hình chỉ cách nhau 100ms khi mọi thứ bình thường).
                if staleTicks >= 5 { disconnected = true }
            }
        }
    }

    private func stopWatching() {
        watchdogTask?.cancel()
        watchdogTask = nil
        guard let id = selectedDesktopId else { return }
        Task {
            _ = try? await SignalRClient.shared.invoke("StopWatchingDesktop", args: [id])
            await SignalRClient.shared.setScreenshotHandler(nil)
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
              let match = desktops.first(where: { $0.value == targetLabel }),
              match.key != selectedDesktopId else { return false }
        selectedDesktopId = match.key
        return true
    }
}
