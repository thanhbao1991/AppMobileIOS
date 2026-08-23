import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`. KHÔNG còn
/// hỏi từng ảnh (poll) — vào màn hình gọi `StartWatchingDesktop` 1 lần, Desktop tự đẩy khung hình
/// liên tục theo nhịp của chính nó (thu nhỏ 60% + JPEG quality thấp) qua `ScreenshotReceived` tới
/// khi rời màn hình gọi `StopWatchingDesktop`; không phải video thật nhưng bỏ hẳn round-trip
/// request-response mỗi khung hình nên mượt hơn hẳn bản poll cũ. 1 watchdog tự gọi lại
/// `StartWatchingDesktop` nếu lâu không có khung hình mới (mạng rớt/reconnect). Giữ nguyên chiều
/// dọc (không tự xoay ngang); 2 ngón để zoom (chỉ zoom chiều ngang, chiều dọc luôn khớp khung xem —
/// không bao giờ hở viền đen), 1 ngón để kéo khung hình đang xem, nút X góc trên để thoát. Mặc định
/// phóng to lấp đầy khung xem (aspectRatio .fill + clip, không phải .fit) — 2 bên trái/phải bị
/// crop, kéo 1 ngón để xem phần bị crop, zoom ra tối đa đúng lúc hết crop (không cho nhỏ hơn nữa).
/// Chạm vào ảnh = click chuột trái tại đúng vị trí đó trên Desktop — gửi `SendClick` ngay lập tức
/// (không chờ khung hình kế), Desktop quy đổi lại toạ độ thật rồi click bằng `ButtonBase.OnClick()`
/// (qua reflection, đúng hành vi click thật) — không qua OS input.
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

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
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
                            .scaleEffect(x: scale, y: 1)
                            .offset(offset)

                        // Gesture gắn vào lớp overlay KHÔNG bị scaleEffect/offset — location/translation
                        // đọc được luôn là toạ độ màn hình thật (viewport), tự quy đổi ngược sang toạ độ
                        // ảnh gốc bằng scale/offset đang biết, không phụ thuộc SwiftUI tự làm việc đó.
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(panGesture(maxOffsetX: maxOffsetX(image: image, frame: geo.size))
                                .simultaneously(with: zoomGesture(image: image, frame: geo.size)))
                            .simultaneousGesture(tapGesture(image: image, frame: geo.size))
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

    // Mặc định (scale = 1) đã lấp đầy khung xem (aspectFill) — không cho zoom vào thêm (tối đa =
    // đúng khung xem). Zoom ra tối đa = đúng điểm ảnh vừa khít chiều ngang (hết phần bị crop) —
    // quá mức đó sẽ hở viền đen 2 bên nên chặn lại, không cho zoom nhỏ hơn nữa.
    private func zoomGesture(image: UIImage, frame: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(1, max(minScale(image: image, frame: frame), lastScale * value))
                // Offset đã kéo (pan) trước đó có thể vượt quá maxOffsetX mới sau khi scale đổi
                // (maxOffsetX tỷ lệ theo scale) — không reclamp sẽ hở viền đen 2 bên khi zoom nhỏ
                // lại sau khi đã pan.
                let maxX = maxOffsetX(image: image, frame: frame)
                offset = CGSize(width: min(maxX, max(-maxX, offset.width)), height: 0)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
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
    /// phình đó (đã nhân theo scale hiện tại) làm giới hạn kéo ngang tối đa mỗi bên.
    private func maxOffsetX(image: UIImage, frame: CGSize) -> CGFloat {
        guard image.size.height > 0, frame.height > 0 else { return 0 }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height
        guard imageAspect > frameAspect else { return 0 }
        let renderedWidth = frame.height * imageAspect
        return max(0, (renderedWidth * scale - frame.width) / 2)
    }

    /// scale nhỏ nhất mà chiều ngang vẫn còn phủ đủ khung xem (renderedWidth * scale == frame.width)
    /// — nhỏ hơn nữa sẽ hở viền đen 2 bên trái/phải.
    private func minScale(image: UIImage, frame: CGSize) -> CGFloat {
        guard image.size.height > 0, frame.height > 0 else { return 1 }
        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height
        guard imageAspect > frameAspect else { return 1 }
        let renderedWidth = frame.height * imageAspect
        return frame.width / renderedWidth
    }

    // Chạm vào ảnh = click chuột trái tại đúng vị trí đó trên Desktop — gửi ngay lập tức.
    private func tapGesture(image: UIImage, frame: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard let point = imagePoint(from: value.location, frame: frame, image: image) else { return }
                let targetId = currentDesktopId
                Task { _ = try? await SignalRClient.shared.invoke(
                    "SendClick", args: [targetId, Double(point.x), Double(point.y)]) }
            }
    }

    /// Quy đổi 1 điểm chạm trên viewport (chưa bị scaleEffect/offset) về đúng toạ độ pixel trong
    /// ảnh cửa sổ Desktop gốc — tự đảo ngược scale/offset (đang biết) rồi đảo ngược phần aspectFill
    /// phình ra ngoài khung xem.
    private func imagePoint(from location: CGPoint, frame: CGSize, image: UIImage) -> CGPoint? {
        guard image.size.width > 0, image.size.height > 0, frame.width > 0, frame.height > 0 else { return nil }

        // scaleEffect chỉ áp theo chiều ngang (x: scale, y: 1) — chiều dọc không transform gì cả.
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        let localX = (location.x - offset.width - center.x) / scale + center.x
        let localY = location.y
        guard localX >= 0, localX <= frame.width, localY >= 0, localY <= frame.height else { return nil }

        let imageAspect = image.size.width / image.size.height
        let frameAspect = frame.width / frame.height

        let renderedWidth: CGFloat
        let renderedHeight: CGFloat
        let contentX: CGFloat
        let contentY: CGFloat
        if imageAspect > frameAspect {
            renderedHeight = frame.height
            renderedWidth = frame.height * imageAspect
            contentX = localX + (renderedWidth - frame.width) / 2
            contentY = localY
        } else {
            renderedWidth = frame.width
            renderedHeight = frame.width / imageAspect
            contentX = localX
            contentY = localY + (renderedHeight - frame.height) / 2
        }

        let imageX = contentX * (image.size.width / renderedWidth)
        let imageY = contentY * (image.size.height / renderedHeight)
        guard imageX >= 0, imageX <= image.size.width, imageY >= 0, imageY <= image.size.height else { return nil }
        return CGPoint(x: imageX, y: imageY)
    }

    private func startWatching() {
        Task {
            await SignalRClient.shared.setScreenshotHandler { data in
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                    lastFrameAt = Date()
                    disconnected = false
                    isReconnecting = false
                }
            }
            _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])
        }

        // Desktop tự đẩy khung hình — không có gì để "hỏi lại" nếu mạng rớt, nên cần tự kiểm tra
        // độ mới của khung hình cuối cùng và chủ động gọi lại StartWatchingDesktop khi cần (bù cho
        // cả 2 trường hợp: máy Desktop reconnect đổi connectionId, HOẶC chính iOS reconnect khiến
        // Desktop đang đẩy nhầm về 1 connectionId cũ đã chết).
        watchdogTask = Task {
            var staleTicks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }

                let stale = Date().timeIntervalSince(lastFrameAt) > 2
                if !stale { staleTicks = 0; continue }

                staleTicks += 1
                _ = await tryResolveNewId()
                _ = try? await SignalRClient.shared.invoke("StartWatchingDesktop", args: [currentDesktopId])

                // ~20s không nhận được khung hình nào dù đã thử gọi lại nhiều lần — báo mất kết nối
                // thật, tránh báo sai vì 1-2 lần hiccup mạng thoáng qua.
                if staleTicks >= 10 { disconnected = true }
            }
        }
    }

    private func tryResolveNewId() async -> Bool {
        guard let desktops = try? await SignalRClient.shared.fetchConnectedDesktops(),
              let match = desktops.first(where: { $0.value == label }),
              match.key != currentDesktopId else { return false }
        currentDesktopId = match.key
        return true
    }
}
