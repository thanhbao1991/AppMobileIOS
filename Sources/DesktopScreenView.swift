import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy đã chọn ở `DesktopPickerView`. Poll
/// ảnh chụp qua hub mỗi ~1.5s (RequestDesktopScreenshot → Desktop tự chụp → ScreenshotReceived),
/// không phải video thật — đủ để canh máy đang chạy gì. Vào màn hình tự xoay ngang + full màn
/// hình, chạm vào ảnh để thoát và quay lại dọc — xem `OrientationLock.swift`.
struct DesktopScreenView: View {
    let desktopId: String
    let label: String

    @Environment(\.dismiss) private var dismiss
    @State private var currentDesktopId: String = ""
    @State private var image: UIImage?
    @State private var disconnected = false
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .onTapGesture { dismiss() }
            } else if disconnected {
                Text("\(label) đã ngắt kết nối")
                    .foregroundStyle(.white)
                    .onTapGesture { dismiss() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .statusBarHidden(true)
        .navigationBarHidden(true)
        .onAppear {
            currentDesktopId = desktopId
            OrientationLock.lockLandscape()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            OrientationLock.lockPortrait()
            Task { await SignalRClient.shared.setScreenshotHandler(nil) }
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
                } catch {
                    // connectionId có thể đổi giữa lúc chọn máy (DesktopPickerView) và lúc poll —
                    // reconnect mạng/IIS làm Desktop tự đăng ký lại với id mới. Thử tự tìm lại theo
                    // tên máy (label) trước khi tính là 1 lần lỗi.
                    if await tryResolveNewId() {
                        continue
                    }
                    // Mạng chập chờn/reconnect thoáng qua rất hay gặp — chỉ báo mất kết nối thật
                    // sau vài lần liên tiếp thất bại (~5s), tránh báo sai vì 1 lần hiccup.
                    consecutiveFailures += 1
                    if consecutiveFailures >= 3 { disconnected = true }
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        Task {
            await SignalRClient.shared.setScreenshotHandler { data in
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                    disconnected = false
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
