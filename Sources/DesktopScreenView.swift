import SwiftUI
import UIKit

/// Xem cửa sổ app Desktop client (POS) đang chạy trên máy `targetLabel` cố định. Chỉ mở từ icon
/// cạnh nút "+" ở tab Hoá đơn (`HoaDonListView`, dạng sheet giống form thêm hoá đơn).
/// (2026-08-27: đổi hẳn từ SignalR push sang HTTP GET polling — Desktop tự POST ảnh HoaDonGrid lên
/// Backend mỗi 1s (xem `DesktopScreenUploader.cs`), view này chỉ GET khung mới nhất mỗi 700ms qua
/// `APIClient.getDesktopScreenFrame`. Không còn khái niệm "kết nối"/connectionId gì để bị lệch —
/// mỗi request độc lập, request trước rớt không ảnh hưởng request sau. Trước đây qua SignalR hub
/// (StartWatchingDesktop/GetConnectedDesktops) đã gặp nhiều bug do phải khớp đúng 1 connectionId
/// đang sống tại đúng thời điểm — xem lịch sử trong memory `project_desktop_screen_view_ios`.)
/// READ-ONLY thuần. Desktop chỉ chụp đúng vùng `HoaDonGrid` (control luôn Visibility=Visible +
/// RenderTargetBitmap) chứ không phải toàn màn hình — nhận được dù Desktop đang xem tab khác. Ảnh
/// hiển thị NGUYÊN TỈ LỆ (`.scaledToFit`, không crop/pan/zoom) để khỏi méo hình.
struct DesktopScreenView: View {
    /// Tên máy cố định — đúng máy POS thật đang chạy Desktop client (xem memory
    /// `feedback_138_kill_no_ask`), không còn cho chọn máy khác nữa.
    private let targetLabel = "DESKTOP-118TMVD"

    @State private var image: UIImage?
    /// Quá lâu không có khung hình mới (Desktop tắt/mất mạng) — server trả kèm tuổi khung hình qua
    /// header, không đo timestamp cục bộ để tránh lệch đồng hồ máy.
    @State private var isStale = false

    @Environment(\.dismiss) private var dismiss

    /// Chiều cao sheet tính THẲNG từ chiều rộng màn hình — xem giải thích trong bản gốc trước đây:
    /// `presentationDetents` phải đặt NGOÀI `NavigationStack` mới được SwiftUI áp dụng đúng.
    private let navBarHeightEstimate: CGFloat = 44
    private var contentHeight: CGFloat { screenWidth / screenAspectRatio }

    var body: some View {
        NavigationStack {
            screenArea
                .background(Color(.systemBackground))
                .navigationTitle("Danh sách hoá đơn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") { dismiss() }
                    }
                }
                .task { await pollLoop() }
        }
        .presentationDetents([.height(contentHeight + navBarHeightEstimate)])
    }

    /// Khung đen chỉ cao vừa đúng theo tỉ lệ ảnh nhận được (Desktop chụp `HoaDonGrid` — thường lùn,
    /// rộng hơn nhiều so với màn hình dọc điện thoại).
    @ViewBuilder
    private var screenArea: some View {
        ZStack {
            Color.black

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }

            if isStale {
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

    /// Poll mỗi 400ms tới khi sheet đóng (`.task` tự huỷ khi view biến mất) — khớp Desktop up mỗi
    /// 500ms (2026-08-27: rút từ 700ms/1s sau khi user thấy độ trễ ~2s rõ rệt). Không tìm thấy khung
    /// (Desktop chưa mở app, chưa từng POST lần nào) hay lỗi mạng chỉ giữ nguyên spinner, không báo
    /// lỗi cho người dùng — máy POS thật hay khởi động Desktop client trễ hơn lúc mở form này.
    private func pollLoop() async {
        while !Task.isCancelled {
            if let result = await APIClient.shared.getDesktopScreenFrame(label: targetLabel),
               let decoded = UIImage(data: result.data) {
                image = decoded
                isStale = result.ageMs > 2000
            } else if image != nil {
                isStale = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }
}
