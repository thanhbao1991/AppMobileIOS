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
/// Desktop+Backend hoàn toàn ổn — không đáng công sức tiếp tục dò lệch toạ độ). Giữ nguyên chiều dọc
/// (không tự xoay ngang), KHÔNG zoom — tỉ lệ cố định sao cho chiều ngang Desktop hiển thị đúng bằng
/// 1.5 lần chiều ngang điện thoại (`fixedScale = 1.5 × minScale`, xem `minScale()`), 1 ngón để kéo
/// trái/phải xem phần còn lại, nút X góc trên để thoát.
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

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

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
                            // Chỉ scale theo chiều NGANG — chiều cao giữ nguyên y=1 luôn khớp đúng
                            // khung xem (aspectFill baseline), không bao giờ hở viền đen trên/dưới.
                            .scaleEffect(x: fixedScale(image: image, frame: geo.size), y: 1)
                            .offset(offset)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(panGesture(maxOffsetX: maxOffsetX(image: image, frame: geo.size)))
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

    // Chỉ cho kéo trái/phải — giữ nguyên chiều dọc. Giới hạn trong đúng phần ảnh bị crop (aspectFill)
    // đang phình ra ngoài khung xem theo scale hiện tại — không kéo quá để lộ nền đen.
    private func panGesture(maxOffsetX: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let newX = lastOffset.width + value.translation.width
                offset = CGSize(width: min(maxOffsetX, max(-maxOffsetX, newX)), height: 0)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    /// Ảnh (aspectFill) phủ hết chiều cao khung xem rồi phình ngang ra ngoài — tính đúng nửa phần
    /// phình đó (đã nhân theo fixedScale) làm giới hạn kéo ngang tối đa mỗi bên.
    private func maxOffsetX(image: UIImage, frame: CGSize) -> CGFloat {
        guard image.size.height > 0, frame.height > 0 else { return 0 }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height
        guard imageAspect > frameAspect else { return 0 }
        let renderedWidth = frame.height * imageAspect
        return max(0, (renderedWidth * fixedScale(image: image, frame: frame) - frame.width) / 2)
    }

    /// scale nhỏ nhất mà chiều ngang vẫn còn phủ đủ khung xem (renderedWidth * scale == frame.width)
    /// — nhỏ hơn nữa sẽ hở viền đen 2 bên trái/phải. Dùng làm mốc cho fixedScale bên dưới.
    private func minScale(image: UIImage, frame: CGSize) -> CGFloat {
        guard image.size.height > 0, frame.height > 0 else { return 1 }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height
        guard imageAspect > frameAspect else { return 1 }
        let renderedWidth = frame.height * imageAspect
        return frame.width / renderedWidth
    }

    /// Tỉ lệ CỐ ĐỊNH (không cho zoom) — chiều ngang Desktop hiển thị đúng bằng 1.5 lần chiều ngang
    /// điện thoại: ở `minScale` toàn bộ chiều ngang Desktop vừa khít 1 màn hình điện thoại, nên
    /// `1.5 × minScale` làm nó trải rộng ra đúng 1.5 màn hình điện thoại (kéo 1 ngón để xem phần
    /// còn lại). Chặn trên = 1 (không zoom sâu hơn mức lấp đầy khung xem mặc định).
    private func fixedScale(image: UIImage, frame: CGSize) -> CGFloat {
        min(1, 1.5 * minScale(image: image, frame: frame))
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
