import SwiftUI

/// Khung tab khớp 5 mục chính trong drawer Android (MainActivity.kt NavId) — chỉ "Hoá đơn" có nội
/// dung thật, còn lại là vỏ "Sắp có" chờ làm sau (đúng yêu cầu: làm Hoá đơn ngày trước).
struct MainTabView: View {
    @Binding var isLoggedIn: Bool

    var body: some View {
        TabView {
            HoaDonListView()
                .tabItem { Label("Hoá đơn", systemImage: "doc.text") }

            PlaceholderTab(title: "Thanh toán", icon: "creditcard")
                .tabItem { Label("Thanh toán", systemImage: "creditcard") }

            PlaceholderTab(title: "Công nợ", icon: "exclamationmark.circle")
                .tabItem { Label("Công nợ", systemImage: "exclamationmark.circle") }

            PlaceholderTab(title: "Chi tiêu", icon: "banknote")
                .tabItem { Label("Chi tiêu", systemImage: "banknote") }

            AccountTab(isLoggedIn: $isLoggedIn)
                .tabItem { Label("Tài khoản", systemImage: "person.circle") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let icon: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 48)).foregroundColor(.textMuted)
                Text("Sắp có").foregroundColor(.textMuted)
            }
            .navigationTitle(title)
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
