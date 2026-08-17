import SwiftUI

/// 5 tab trên thanh menu: 4 tab dùng hàng ngày (Hoá đơn/Thanh toán/Công nợ/Chi tiêu) + 1 tab
/// "Menu" gom Thống kê/Công việc/Tài khoản dạng menu — giữ đúng pattern Android dùng khi
/// vượt quá 5 mục (bottom sheet "Khác"), dù iOS TabView tự tạo "More" tự động cũng được, gom tay
/// vẫn rõ ràng và dễ kiểm soát hơn để 8 tab dồn hết vào 1 mục "More" xa lạ với UX iOS quen thuộc.
/// Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu — làm sau cùng CreatePlus).
struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    @ObservedObject private var activeTab = ActiveTab.shared
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HoaDonListView()
                .tabItem { Label("Hoá đơn", systemImage: "doc.text") }
                .tag(0)

            ThanhToanListView()
                .tabItem { Label("Thanh toán", systemImage: "creditcard") }
                .tag(1)

            CongNoListView()
                .tabItem { Label("Công nợ", systemImage: "exclamationmark.circle") }
                .tag(2)

            ChiTieuListView()
                .tabItem { Label("Chi tiêu", systemImage: "banknote") }
                .tag(3)

            MoreMenuView(isLoggedIn: $isLoggedIn)
                .tabItem { Label("Menu", systemImage: "ellipsis.circle") }
                .tag(4)
        }
        .onChange(of: selection) { newValue in
            switch newValue {
            case 0: activeTab.tab = .hoaDon
            case 1: activeTab.tab = .thanhToan
            case 2: activeTab.tab = .congNo
            case 3: activeTab.tab = .chiTieu
            default: activeTab.tab = .other
            }
        }
    }
}

private struct MoreMenuView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ThongKeView()
                    } label: {
                        Label("Thống kê", systemImage: "chart.pie")
                    }
                    NavigationLink {
                        CongViecListView()
                    } label: {
                        Label("Công việc", systemImage: "checklist")
                    }
                }

                Section {
                    if let name = Prefs.displayName, !name.isEmpty {
                        Label(name, systemImage: "person.circle")
                    }
                    Button(role: .destructive) {
                        Prefs.clear()
                        isLoggedIn = false
                    } label: {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}
