import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`. Poll
/// ảnh chụp qua hub mỗi ~0.1s (RequestDesktopScreenshot → Desktop tự chụp → ScreenshotReceived),
/// không phải video thật — đủ để canh máy đang chạy gì. Giữ nguyên chiều dọc (không tự xoay ngang);
/// 2 ngón để zoom, 1 ngón để kéo khung hình đang xem, nút X góc trên để thoát.
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
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(panGesture.simultaneously(with: zoomGesture))
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

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, lastScale * value)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
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
