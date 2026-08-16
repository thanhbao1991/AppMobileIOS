import SwiftUI

/// 5 tab trên thanh menu: 4 tab dùng hàng ngày (Hoá đơn/Thanh toán/Công nợ/Chi tiêu) + 1 tab
/// "Thêm" gom Công việc/Báo cáo/Thống kê/Tài khoản dạng menu — giữ đúng pattern Android dùng khi
/// vượt quá 5 mục (bottom sheet "Khác"), dù iOS TabView tự tạo "More" tự động cũng được, gom tay
/// vẫn rõ ràng và dễ kiểm soát hơn để 8 tab dồn hết vào 1 mục "More" xa lạ với UX iOS quen thuộc.
/// Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu — làm sau cùng CreatePlus).
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

            MoreMenuView(isLoggedIn: $isLoggedIn)
                .tabItem { Label("Thêm", systemImage: "ellipsis.circle") }
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
                        CongViecListView()
                    } label: {
                        Label("Công việc", systemImage: "checklist")
                    }
                    NavigationLink {
                        BaoCaoMenuView()
                    } label: {
                        Label("Báo cáo", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        ThongKeView()
                    } label: {
                        Label("Thống kê", systemImage: "chart.pie")
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
            .navigationTitle("Thêm")
        }
    }
}
