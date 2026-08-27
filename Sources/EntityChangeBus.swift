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
    private var toastDismissTask: Task<Void, Never>?

    func post(_ entityName: String, _ action: String, _ id: String, voice: String = "") {
        lastEvent = EntityChangedEvent(entityName: entityName, action: action, id: id)
        notifyReceived(entityName: entityName, action: action, voice: voice)
    }

    /// Rung + "ting" mỗi khi app đang mở nhận signal real-time (bất kể entity nào) — cho nhân viên
    /// biết có cập nhật mới mà không cần dán mắt vào màn hình. post() chỉ được gọi từ callback
    /// SignalRClient (xem ContentView) nên chỉ kêu khi kết nối đang sống, tức app đang mở.
    private func notifyReceived(entityName: String, action: String, voice: String) {
        AudioServicesPlaySystemSound(1007) // SMS-received1 — "ting" ngắn, quen thuộc
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        toastText = Self.reasonText(entityName: entityName, action: action, voice: voice)
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toastText = nil
        }
    }

    /// voice là chuỗi "hiển thị||đọc" backend gửi kèm (xem BaseApiController.NotifyEntityChanged) —
    /// lấy phần hiển thị. Nếu backend không gửi voice riêng cho signal này (đa số action CRUD
    /// thường), tự ghép "tên thực thể + hành động" ra tiếng Việt để vẫn có gì đó hiện lên.
    private static func reasonText(entityName: String, action: String, voice: String) -> String {
        let display = voice.components(separatedBy: "||").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if !display.isEmpty { return display }
        return "\(entityLabel(entityName)) \(actionLabel(action))"
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

    private static func actionLabel(_ action: String) -> String {
        switch action {
        case "created": return "mới"
        case "updated": return "vừa cập nhật"
        case "deleted": return "vừa xoá"
        case "reordered": return "sắp xếp lại"
        case "F4": return "vừa thu tiền"
        case "F4Auto": return "tự thu chuyển khoản"
        case "F12": return "ghi nợ"
        case "ESC", "ESC_KHANH": return "chuyển đi ship"
        case "ROLLBACK": return "hoàn tác"
        case "PRINT": return "yêu cầu in"
        default: return "có cập nhật"
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
