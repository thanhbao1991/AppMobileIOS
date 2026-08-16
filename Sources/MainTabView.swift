import SwiftUI

/// 6 tab chính có nội dung thật + Tài khoản. Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu —
/// làm sau cùng CreatePlus). iOS TabView tự gom vào "More" nếu vượt 5 item, không giới hạn cứng
/// như BottomNavigationView bên Android nên không cần Drawer riêng.
struct MainTabView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        TabView {
            HoaDonListView()
                .tabItem { Label("Hoá đơn", systemImage: "doc.text") }

            ThanhToanListView()
                .tabItem { Label("Thanh toán", systemImage: "creditcard") }

            CongNoListView()
                .tabItem { Label("Công nợ", systemImage: "exclamationmark.circle") }

            ChiTieuListView()
                .tabItem { Label("Chi tiêu", systemImage: "banknote") }

            CongViecListView()
                .tabItem { Label("Công việc", systemImage: "checklist") }

            BaoCaoMenuView()
                .tabItem { Label("Báo cáo", systemImage: "chart.bar") }

            AccountTab(isLoggedIn: $isLoggedIn)
                .tabItem { Label("Tài khoản", systemImage: "person.circle") }
        }
    }
}

private struct AccountTab: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        NavigationStack {
            List {
                if let name = Prefs.displayName, !name.isEmpty {
                    Text(name)
                }
                Button("Đăng xuất", role: .destructive) {
                    Prefs.clear()
                    isLoggedIn = false
                }
            }
            .navigationTitle("Tài khoản")
        }
    }
}
