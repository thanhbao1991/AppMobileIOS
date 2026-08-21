import Foundation

/// Xử lý link "trasuaapp://khachhang/{id}" — link này được ContactSyncService ghi vào field URL
/// của contact khi đồng bộ Danh bạ, để nhân viên bấm ngay sau khi cúp máy (từ contact/Recents)
/// mở thẳng app vào form tạo đơn Ship, prefill đúng khách vừa gọi.
@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    /// MainTabView chuyển sang tab Hoá đơn khi giá trị này đổi thành non-nil; HoaDonListView đọc
    /// rồi tự set về nil sau khi đã mở sheet tạo đơn, tránh mở lại nếu view rebuild.
    @Published var khachHangIdToOrder: String?

    func handle(_ url: URL) {
        guard url.scheme == "trasuaapp", url.host == "khachhang" else { return }
        let id = url.pathComponents.first { $0 != "/" }
        guard let id, !id.isEmpty else { return }
        khachHangIdToOrder = id
    }
}
