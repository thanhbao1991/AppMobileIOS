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
/// Điều khiển: TOÀN BỘ gesture xử lý qua 1 view raw-touch duy nhất (`RemoteControlSurface`, xem
/// `KeyCaptureView.swift`) — không compose nhiều gesture recognizer độc lập, tránh xung đột (1 ngón
/// và 2 ngón nằm trên các recognizer khác nhau từng gây vừa gửi lệnh chuột vừa cuộn cùng lúc; 2 ngón
/// cũng tự phân định RÕ 1 trong 2 hành vi cuộn/zoom cho trọn lượt chạm, tránh vừa cuộn vừa zoom giật
/// do rung tay). Ngữ nghĩa: 1 ngón CHẠM (không đáng kể di chuyển) = click chuột trái thật tại đúng
/// điểm đó (move+down+up qua Win32 SendInput phía Desktop); GIỮ YÊN đủ lâu (long-press) = click chuột
/// phải; 1 ngón KÉO thật sự = pan khung nhìn (hoạt động ở mọi mức zoom, kể cả chưa zoom — để xem phần
/// bị crop do màn hình điện thoại không tỉ lệ khớp màn hình Desktop); 2 ngón kéo = cuộn; pinch 2 ngón
/// = zoom KHUNG NHÌN (không đổi độ phân giải Desktop thật) — nhỏ nhất tới `minScale()` (thấy TOÀN BỘ
/// màn hình Desktop, không crop chiều nào) tới lớn nhất 4x (zoom sâu để bấm chính xác). Nút bàn phím
/// góc trên bật `KeyCaptureView` để gõ phím thật. `imagePoint()` quy đổi toạ độ chạm trên khung nhìn
/// (đã bị scale/offset do zoom) về đúng pixel trong ảnh Desktop gốc.
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

    // Zoom khung nhìn — KHÔNG đổi độ phân giải capture bên Desktop, chỉ đổi phần ảnh đang hiển
    // thị/quy đổi toạ độ. scale = 1 (mặc định) = không zoom. onPinch cho ratio tăng dần mỗi lần
    // move (distance/lastDistance) nên cập nhật nhân dồn trực tiếp, không cần snapshot lastScale.
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

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
                            .scaleEffect(scale)
                            .offset(offset)

                        RemoteControlSurface(
                            onTap: { location in handleTap(at: location, frame: geo.size, image: image) },
                            onLongPress: { location in handleLongPress(at: location, frame: geo.size, image: image) },
                            onPan: { delta in handlePan(delta: delta, frame: geo.size, image: image) },
                            onScroll: { location, deltaY in handleScroll(at: location, deltaY: deltaY, frame: geo.size, image: image) },
                            onPinch: { factor in handlePinch(factor: factor, frame: geo.size, image: image) })
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

    // Chạm (không di chuyển đáng kể) = click chuột trái thật — 1 lượt move+down+up atomic tại đúng
    // điểm chạm, không có bước "move" rời trước đó (khác kéo-giữ-nút kiểu cũ).
    private func handleTap(at location: CGPoint, frame: CGSize, image: UIImage) {
        guard let point = imagePoint(from: location, frame: frame, image: image) else { return }
        let targetId = currentDesktopId
        Task {
            _ = try? await SignalRClient.shared.invoke(
                "SendMouseDown", args: [targetId, Double(point.x), Double(point.y)])
            _ = try? await SignalRClient.shared.invoke(
                "SendMouseUp", args: [targetId, Double(point.x), Double(point.y)])
        }
    }

    // Giữ yên (không di chuyển) đủ lâu = click chuột phải.
    private func handleLongPress(at location: CGPoint, frame: CGSize, image: UIImage) {
        guard let point = imagePoint(from: location, frame: frame, image: image) else { return }
        let targetId = currentDesktopId
        Task { _ = try? await SignalRClient.shared.invoke(
            "SendRightClick", args: [targetId, Double(point.x), Double(point.y)]) }
    }

    // 1 ngón kéo thật sự = pan khung nhìn — hoạt động ở MỌI mức scale (kể cả scale=1 mặc định, để
    // xem phần bị crop do màn hình điện thoại không tỉ lệ khớp màn hình Desktop), không gửi lệnh
    // chuột gì trong lúc kéo. clampOffset tự trả về 0 ở những chiều/scale không còn gì để pan.
    private func handlePan(delta: CGSize, frame: CGSize, image: UIImage) {
        offset = clampOffset(
            CGSize(width: offset.width + delta.width, height: offset.height + delta.height),
            scale: scale, frame: frame, image: image)
    }

    private func handleScroll(at location: CGPoint, deltaY: CGFloat, frame: CGSize, image: UIImage) {
        guard let point = imagePoint(from: location, frame: frame, image: image) else { return }
        let targetId = currentDesktopId
        Task { _ = try? await SignalRClient.shared.invoke(
            "SendMouseScroll", args: [targetId, Double(point.x), Double(point.y), Double(-deltaY) * 3]) }
    }

    // factor = tỉ lệ khoảng cách 2 ngón hiện tại / lần trước (RemoteControlSurfaceView đã tính sẵn)
    // — nhân dồn trực tiếp vào scale. Chặn dưới = minScale(image,frame) (đủ nhỏ để thấy TOÀN BỘ màn
    // hình Desktop, không crop chiều nào) thay vì cứng 1, chặn trên = 4 (zoom sâu để bấm chính xác).
    // KHÔNG đổi độ phân giải capture Desktop, chỉ đổi khung nhìn.
    private func handlePinch(factor: CGFloat, frame: CGSize, image: UIImage) {
        scale = max(minScale(image: image, frame: frame), min(4, scale * factor))
        offset = clampOffset(offset, scale: scale, frame: frame, image: image)
    }

    /// Kích thước ảnh sau `.scaledToFill()` (TRƯỚC `scaleEffect(scale)`) — 1 chiều luôn khớp đúng
    /// frame (chiều "vừa khít"), chiều còn lại phình ra ngoài (chiều bị crop ở scale=1 mặc định).
    private func baselineRenderedSize(image: UIImage, frame: CGSize) -> CGSize {
        guard image.size.height > 0, frame.height > 0 else { return frame }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height
        if imageAspect > frameAspect {
            return CGSize(width: frame.height * imageAspect, height: frame.height)
        } else {
            return CGSize(width: frame.width, height: frame.width / imageAspect)
        }
    }

    /// scale nhỏ nhất để không còn crop chiều nào (toàn bộ ảnh Desktop vừa đúng khung xem, có thể
    /// hở viền đen 2 bên/trên-dưới nếu tỉ lệ khác nhau) — đúng lúc renderedSize0*scale khớp frame ở
    /// chiều đang bị crop tại baseline; chiều kia tự động vừa khít vì cùng tỉ lệ ảnh gốc.
    private func minScale(image: UIImage, frame: CGSize) -> CGFloat {
        let size0 = baselineRenderedSize(image: image, frame: frame)
        guard size0.width > 0, size0.height > 0 else { return 1 }
        return min(frame.width / size0.width, frame.height / size0.height)
    }

    /// scaleEffect(scale) phóng to/thu nhỏ quanh tâm khung xem một content đã có kích thước baseline
    /// (`baselineRenderedSize`) — phần phình/hụt so với frame ở scale bất kỳ chỉ đơn giản là
    /// size0*scale - frame mỗi chiều, đúng cho cả scale<1 (zoom ra) lẫn scale>1 (zoom vào).
    private func clampOffset(_ o: CGSize, scale: CGFloat, frame: CGSize, image: UIImage) -> CGSize {
        let size0 = baselineRenderedSize(image: image, frame: frame)
        let maxX = max(0, (size0.width * scale - frame.width) / 2)
        let maxY = max(0, (size0.height * scale - frame.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    /// Quy đổi 1 điểm chạm trên khung nhìn (đã bị scaleEffect/offset do zoom) về đúng toạ độ pixel
    /// trong ảnh cửa sổ Desktop gốc — đảo ngược zoom trước, rồi đảo ngược phần aspectFill phình ra
    /// ngoài khung xem (baseline, độc lập với zoom).
    private func imagePoint(from location: CGPoint, frame: CGSize, image: UIImage) -> CGPoint? {
        guard image.size.width > 0, image.size.height > 0, frame.width > 0, frame.height > 0 else { return nil }

        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let localX = (location.x - offset.width - center.x) / scale + center.x
        let localY = (location.y - offset.height - center.y) / scale + center.y
        guard localX >= 0, localX <= frame.width, localY >= 0, localY <= frame.height else { return nil }

        let size0 = baselineRenderedSize(image: image, frame: frame)
        let contentX = localX + (size0.width - frame.width) / 2
        let contentY = localY + (size0.height - frame.height) / 2

        let imageX = contentX * (image.size.width / size0.width)
        let imageY = contentY * (image.size.height / size0.height)
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
