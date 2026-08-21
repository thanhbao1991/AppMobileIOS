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
            while !Task.isCancelled {
                do {
                    _ = try await SignalRClient.shared.invoke("RequestDesktopScreenshot", args: [desktopId])
                } catch {
                    disconnected = true
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
}
