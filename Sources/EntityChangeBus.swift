import AudioToolbox
import Foundation
import SwiftUI

/// Tab hiện đang xem — set bởi MainTabView, đọc bởi các List view để quyết định có tự làm mới khi
/// nhận signal hay không (chỉ tab đang xem mới reload, tab khác chờ đến khi user chuyển sang).
enum AppTab { case hoaDon, thanhToan, congNo, chiTieu, congViec, other }

@MainActor
final class ActiveTab: ObservableObject {
    static let shared = ActiveTab()
    @Published var tab: AppTab = .hoaDon
}

struct EntityChangedEvent: Equatable {
    let entityName: String
    let action: String
    let id: String
    let ts = Date()

    static func == (lhs: EntityChangedEvent, rhs: EntityChangedEvent) -> Bool { lhs.ts == rhs.ts }
}

/// Cầu nối SignalRClient → SwiftUI. Mỗi List view subscribe qua .onChange(of: bus.lastEvent) và tự
/// lọc theo entityName + ActiveTab.shared.tab liên quan đến mình.
@MainActor
final class EntityChangeBus: ObservableObject {
    static let shared = EntityChangeBus()
    @Published var lastEvent: EntityChangedEvent?
    /// Câu ngắn giải thích tại sao vừa rung — hiện qua ToastBannerView (xem ContentView) rồi tự tắt.
    /// Trước đây rung/"ting" xong không hiện gì, nhân viên không biết vừa có chuyện gì mà phải tự mở
    /// app dò từng tab.
    @Published var toastText: String?
    /// Nhãn ngắn đứng đầu banner (vd "Thu tiền mặt", "Xoá đơn") — TÁCH riêng khỏi toastText để hiện
    /// đậm/khác cỡ chữ với phần chi tiết, khớp phản hồi "đọc khó hiểu" (trước đây chỉ có mỗi phần
    /// chi tiết "Bàn 5 120.000" không nói rõ vừa xảy ra chuyện gì).
    @Published var toastLabel: String = ""
    @Published var toastColor: Color = .brandPrimary
    @Published var toastIcon: String = "bell.fill"
    private var toastDismissTask: Task<Void, Never>?

    func post(_ entityName: String, _ action: String, _ id: String, voice: String = "") {
        lastEvent = EntityChangedEvent(entityName: entityName, action: action, id: id)
        notifyReceived(entityName: entityName, action: action, voice: voice)
    }

    /// Vuốt lên để tắt SỚM banner đang hiện (SignalToastBanner) — chỉ tắt cái đang hiện, không tắt
    /// cơ chế thông báo nói chung, signal tiếp theo vẫn hiện bình thường.
    func dismissToast() {
        toastDismissTask?.cancel()
        toastText = nil
    }

    /// Rung + "ting" mỗi khi app đang mở nhận signal real-time (bất kể entity nào) — cho nhân viên
    /// biết có cập nhật mới mà không cần dán mắt vào màn hình. post() chỉ được gọi từ callback
    /// SignalRClient (xem ContentView) nên chỉ kêu khi kết nối đang sống, tức app đang mở.
    private func notifyReceived(entityName: String, action: String, voice: String) {
        AudioServicesPlaySystemSound(1007) // SMS-received1 — "ting" ngắn, quen thuộc
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        let style = Self.style(entityName: entityName, action: action)
        toastLabel = style.label
        toastColor = style.color
        toastIcon = style.icon
        toastText = Self.reasonText(voice: voice)
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toastText = nil
        }
    }

    /// voice là chuỗi "hiển thị||đọc" backend gửi kèm (xem BaseApiController.NotifyEntityChanged) —
    /// lấy phần hiển thị làm dòng chi tiết bên dưới nhãn đậm (toastLabel). Rỗng nếu backend không
    /// gửi voice riêng cho signal này (vd ROLLBACK/PRINT) — banner chỉ còn icon + nhãn, khỏi lặp lại
    /// ý ("Hoàn tác thanh toán" + "Hoá đơn hoàn tác" trùng nghĩa).
    private static func reasonText(voice: String) -> String {
        voice.components(separatedBy: "||").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Nhãn + màu + icon theo (entityName, action) — quyết định nền banner và chữ đậm đầu dòng.
    /// Màu khớp bộ token dùng xuyên suốt app (HoaDonFormatting.swift): xanh dương = tạo/thu CK, xanh
    /// lá = thu tiền mặt, đỏ = xoá/ghi nợ, vàng = sửa/hoàn tác, hồng = ship, xám = khác.
    private static func style(entityName: String, action: String) -> (label: String, color: Color, icon: String) {
        if entityName.lowercased() == "hoadon" {
            switch action {
            case "CREATE": return ("Đơn mới", .brandPrimary, "plus.circle.fill")
            case "UPDATE": return ("Sửa đơn", .warningColor, "pencil.circle.fill")
            case "DEL": return ("Xoá đơn", .dangerColor, "trash.circle.fill")
            case "F1": return ("Thu tiền mặt", .successColor, "banknote.fill")
            case "F4": return ("Thu chuyển khoản", .brandPrimary, "creditcard.fill")
            case "F4Auto": return ("Tự thu chuyển khoản", .brandPrimary, "sparkles")
            case "F12": return ("Ghi nợ", .dangerColor, "exclamationmark.circle.fill")
            case "ESC", "ESC_KHANH": return ("Chuyển đi ship", .pinkColor, "scooter")
            case "ROLLBACK": return ("Hoàn tác thanh toán", .warningColor, "arrow.uturn.backward.circle.fill")
            case "PRINT": return ("Yêu cầu in", .textMuted, "printer.fill")
            default: break
            }
        }
        switch action {
        case "created": return ("\(entityLabel(entityName)) mới", .brandPrimary, "plus.circle.fill")
        case "updated": return ("\(entityLabel(entityName)) cập nhật", .warningColor, "pencil.circle.fill")
        case "deleted": return ("\(entityLabel(entityName)) đã xoá", .dangerColor, "trash.circle.fill")
        case "reordered": return ("\(entityLabel(entityName)) sắp xếp lại", .textMuted, "arrow.up.arrow.down.circle.fill")
        default: return (entityLabel(entityName), .textMuted, "bell.fill")
        }
    }

    private static func entityLabel(_ entityName: String) -> String {
        switch entityName.lowercased() {
        case "hoadon": return "Hoá đơn"
        case "khachhang": return "Khách hàng"
        case "chitiethoadonthanhtoan": return "Thanh toán"
        case "chitieuhangngay": return "Chi tiêu"
        case "congviecnoibo": return "Công việc"
        case "phiendangnhap": return "Đăng nhập"
        case "sanpham": return "Sản phẩm"
        case "nguyenlieu": return "Nguyên liệu"
        default: return entityName
        }
    }

}

private struct EntityChangeListener: ViewModifier {
    let entityNames: Set<String>
    let tab: AppTab
    let action: () -> Void
    @ObservedObject private var bus = EntityChangeBus.shared
    @ObservedObject private var activeTab = ActiveTab.shared

    func body(content: Content) -> some View {
        content.onChange(of: bus.lastEvent) { event in
            guard let event, entityNames.contains(event.entityName), activeTab.tab == tab else { return }
            action()
        }
    }
}

extension View {
    /// Tự làm mới khi nhận signal thuộc 1 trong entityNames, CHỈ khi tab đang xem (activeTab) trùng tab.
    func onEntityChanged(_ entityNames: Set<String>, tab: AppTab, perform: @escaping () -> Void) -> some View {
        modifier(EntityChangeListener(entityNames: entityNames, tab: tab, action: perform))
    }
}
