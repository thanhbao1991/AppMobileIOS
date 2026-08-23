import SwiftUI
import UIKit

/// Xem + ĐIỀU KHIỂN cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`.
/// Luôn ở chế độ điều khiển ngay khi vào màn hình — không có công tắc "chỉ xem" nữa. KHÔNG hỏi từng
/// ảnh (poll) — vào màn hình gọi `StartWatchingDesktop` 1 lần, Desktop tự đẩy khung hình liên tục
/// theo nhịp của chính nó qua `ScreenshotReceived` tới khi rời màn hình gọi `StopWatchingDesktop`.
/// Mỗi khung hình chỉ là DIRTY-RECT (dải ngang đã đổi so với lần trước, x/y/w/h kèm ảnh) — Desktop bỏ
/// qua hoàn toàn lượt gửi nếu màn hình đứng yên (thường xuyên với POS), chỉ gửi full-frame lúc khung
/// đầu tiên + định kỳ ~150 lượt để tự "chữa lành". `applyFrame()` vẽ đè patch lên canvas (`image`)
/// đang hiển thị thay vì thay hẳn ảnh mỗi lần. 1 watchdog tự gọi lại `StartWatchingDesktop` nếu lâu
/// không có khung hình mới (mạng rớt/reconnect) — ngưỡng phải RỘNG (10s) vì màn hình đứng yên hợp lệ
/// cũng không có khung hình mới trong lúc đó.
///
/// Điều khiển: 1 ngón kéo = chuột thật (move+down+up qua Win32 SendInput phía Desktop, xem
/// `controlGesture`), 2 ngón kéo = cuộn (`TwoFingerScrollView`), nút bàn phím góc trên bật
/// `KeyCaptureView` để gõ phím thật vào Desktop. Ảnh luôn phóng to lấp đầy khung xem (aspectFill,
/// không pan/zoom được nữa) — `imagePoint()` quy đổi toạ độ chạm về đúng pixel trong ảnh gốc.
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

    @State private var isKeyboardActive = false
    @State private var isDraggingControl = false
    @State private var lastMoveSentAt: Date = .distantPast

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(controlGesture(image: image, frame: geo.size))
                        TwoFingerScrollView { location, deltaY in
                            guard let point = imagePoint(from: location, frame: geo.size, image: image) else { return }
                            let targetId = currentDesktopId
                            Task { _ = try? await SignalRClient.shared.invoke(
                                "SendMouseScroll", args: [targetId, Double(point.x), Double(point.y), Double(-deltaY) * 3]) }
                        }
                    }
                }
                .clipped()
            } else if disconnected {
                Text("\(label) đã ngắt kết nối")
                    .foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Spacer()

                    Button { isKeyboardActive.toggle() } label: {
                        Image(systemName: isKeyboardActive ? "keyboard.chevron.compact.down" : "keyboard")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
                Spacer()
            }

            KeyCaptureView(isActive: $isKeyboardActive, onText: { text in
                let targetId = currentDesktopId
                Task { _ = try? await SignalRClient.shared.invoke("SendKeyText", args: [targetId, text]) }
            }, onSpecial: { key in
                let targetId = currentDesktopId
                Task { _ = try? await SignalRClient.shared.invoke("SendKeySpecial", args: [targetId, key]) }
            })
            .frame(width: 0, height: 0)

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

    // Luôn ở chế độ điều khiển: 1 ngón kéo = chuột thật (move+down+up qua Win32 SendInput phía Desktop).
    // DragGesture(minimumDistance: 0) tự nhiên phủ luôn trường hợp tap-không-di-chuyển = click
    // (down rồi up ngay tại cùng toạ độ), không cần tapGesture riêng nữa. Throttle MouseMove ~30ms
    // giống nhịp capture Desktop, tránh spam quá nhiều lệnh trong 1 lần kéo dài.
    private func controlGesture(image: UIImage, frame: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let point = imagePoint(from: value.location, frame: frame, image: image) else { return }
                let targetId = currentDesktopId
                if !isDraggingControl {
                    isDraggingControl = true
                    lastMoveSentAt = .distantPast
                    Task { _ = try? await SignalRClient.shared.invoke(
                        "SendMouseDown", args: [targetId, Double(point.x), Double(point.y)]) }
                } else {
                    let now = Date()
                    guard now.timeIntervalSince(lastMoveSentAt) >= 0.03 else { return }
                    lastMoveSentAt = now
                    Task { _ = try? await SignalRClient.shared.invoke(
                        "SendMouseMove", args: [targetId, Double(point.x), Double(point.y)]) }
                }
            }
            .onEnded { value in
                isDraggingControl = false
                guard let point = imagePoint(from: value.location, frame: frame, image: image) else { return }
                let targetId = currentDesktopId
                Task { _ = try? await SignalRClient.shared.invoke(
                    "SendMouseUp", args: [targetId, Double(point.x), Double(point.y)]) }
            }
    }

    /// Quy đổi 1 điểm chạm trên viewport về đúng toạ độ pixel trong ảnh cửa sổ Desktop gốc — đảo
    /// ngược phần aspectFill phình ra ngoài khung xem (ảnh luôn phóng to lấp đầy, không pan/zoom).
    private func imagePoint(from location: CGPoint, frame: CGSize, image: UIImage) -> CGPoint? {
        guard image.size.width > 0, image.size.height > 0, frame.width > 0, frame.height > 0,
              location.x >= 0, location.x <= frame.width, location.y >= 0, location.y <= frame.height
        else { return nil }

        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height

        let renderedWidth: CGFloat
        let renderedHeight: CGFloat
        let contentX: CGFloat
        let contentY: CGFloat
        if imageAspect > frameAspect {
            renderedHeight = frame.height
            renderedWidth = frame.height * imageAspect
            contentX = location.x + (renderedWidth - frame.width) / 2
            contentY = location.y
        } else {
            renderedWidth = frame.width
            renderedHeight = frame.width / imageAspect
            contentX = location.x
            contentY = location.y + (renderedHeight - frame.height) / 2
        }

        let imageX = contentX * (image.size.width / renderedWidth)
        let imageY = contentY * (image.size.height / renderedHeight)
        guard imageX >= 0, imageX <= image.size.width, imageY >= 0, imageY <= image.size.height else { return nil }
        return CGPoint(x: imageX, y: imageY)
    }

    private func startWatching() {
        Task {
            await SignalRClient.shared.setScreenshotHandler { data, x, y, w, h in
                applyFrame(data, x: x, y: y, w: w, h: h)
            }
            _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])
        }

        // Desktop tự đẩy khung hình — không có gì để "hỏi lại" nếu mạng rớt, nên cần tự kiểm tra
        // độ mới của khung hình cuối cùng và chủ động gọi lại StartWatchingDesktop khi cần (bù cho
        // cả 2 trường hợp: máy Desktop reconnect đổi connectionId, HOẶC chính iOS reconnect khiến
        // Desktop đang đẩy nhầm về 1 connectionId cũ đã chết). Ngưỡng "lâu không thấy gì" phải RỘNG
        // hơn hẳn 1 khung hình đơn lẻ — giờ Desktop chỉ gửi khi có gì đổi (dirty-rect) + 1 khung hình
        // "chữa lành" định kỳ mỗi ~150 lượt chụp (~6s), nên màn hình đứng yên hoàn toàn cũng có thể
        // hợp lệ không có khung hình mới suốt vài giây — không phải dấu hiệu mất kết nối.
        watchdogTask = Task {
            var staleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                let stale = Date().timeIntervalSince(lastFrameAt) > 10
                if !stale { staleTicks = 0; continue }

                staleTicks += 1
                _ = await tryResolveNewId()
                _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])

                // ~10s (ngưỡng stale) + ~30s thử lại nhiều lần vẫn không có gì — báo mất kết nối thật.
                if staleTicks >= 15 { disconnected = true }
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
