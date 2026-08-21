import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`. Poll
/// ảnh chụp qua hub mỗi ~0.1s (RequestDesktopScreenshot → Desktop tự chụp → ScreenshotReceived),
/// không phải video thật — đủ để canh máy đang chạy gì. Giữ nguyên chiều dọc (không tự xoay ngang);
/// 2 ngón để zoom, 1 ngón để kéo khung hình đang xem, nút X góc trên để thoát. Mặc định phóng to
/// theo chiều cao chiếm hết khung xem (aspectRatio .fill + clip, không phải .fit) — 2 bên trái/phải
/// bị crop, kéo 1 ngón để xem phần bị crop.
struct DesktopScreenView: View {
    let desktopId: String
    let label: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentDesktopId: String = ""
    @State private var image: UIImage?
    @State private var disconnected = false
    @State private var isReconnecting = false
    @State private var pollTask: Task<Void, Never>?

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(panGesture(maxOffsetX: maxOffsetX(image: image, frame: geo.size))
                            .simultaneously(with: zoomGesture))
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
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            Task { await SignalRClient.shared.setScreenshotHandler(nil) }
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active { isReconnecting = true }
        }
    }

    // Mặc định (scale = 1) đã lấp đầy chiều cao khung xem (aspectFill) — không cho zoom vào thêm
    // (tối đa = đúng khung xem), chỉ cho zoom ra (thu nhỏ, tối thiểu 0.1) để xem lại phần bị crop.
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(1, max(0.1, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
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

    private func startPolling() {
        pollTask = Task {
            var consecutiveFailures = 0
            while !Task.isCancelled {
                do {
                    _ = try await SignalRClient.shared.invoke("RequestDesktopScreenshot", args: [currentDesktopId])
                    consecutiveFailures = 0
                    disconnected = false
                    isReconnecting = false
                } catch {
                    // connectionId có thể đổi giữa lúc chọn máy (DesktopPickerView) và lúc poll —
                    // reconnect mạng/IIS làm Desktop tự đăng ký lại với id mới. Thử tự tìm lại theo
                    // tên máy (label) trước khi tính là 1 lần lỗi.
                    if await tryResolveNewId() {
                        continue
                    }
                    // Mạng chập chờn/reconnect thoáng qua rất hay gặp — chỉ báo mất kết nối thật
                    // sau vài lần liên tiếp thất bại (~5s ở poll 0.1s/lần), tránh báo sai vì 1 lần hiccup.
                    consecutiveFailures += 1
                    if consecutiveFailures >= 50 { disconnected = true }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        Task {
            await SignalRClient.shared.setScreenshotHandler { data in
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                    disconnected = false
                    isReconnecting = false
                }
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
