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

    func post(_ entityName: String, _ action: String, _ id: String) {
        lastEvent = EntityChangedEvent(entityName: entityName, action: action, id: id)
        notifyReceived()
    }

    /// Rung + "ting" mỗi khi app đang mở nhận signal real-time (bất kể entity nào) — cho nhân viên
    /// biết có cập nhật mới mà không cần dán mắt vào màn hình. post() chỉ được gọi từ callback
    /// SignalRClient (xem ContentView) nên chỉ kêu khi kết nối đang sống, tức app đang mở.
    private func notifyReceived() {
        AudioServicesPlaySystemSound(1007) // SMS-received1 — "ting" ngắn, quen thuộc
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
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
