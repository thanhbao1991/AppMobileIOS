import SwiftUI

/// Danh sách các máy Desktop client (TraSuaApp.Desktop) đang mở app và đã đăng ký với hub — chọn 1
/// máy để vào xem/điều khiển. [ĐÃ BỎ 2026-08-24] khoá cứng chỉ vào thẳng 1 máy theo tên cố định —
/// khôi phục lại chọn tay vì cần chọn được cả máy dev khi test tính năng mới.
struct DesktopPickerView: View {
    @State private var desktops: [(id: String, label: String)] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading && desktops.isEmpty {
                ProgressView()
            } else if desktops.isEmpty {
                // Vuốt xuống để làm mới thay vì nút "Thử lại" — ScrollView cần content cao hơn 0 để
                // gesture kéo nhận được dù danh sách rỗng.
                ScrollView {
                    Text(errorMessage ?? "Không có máy nào đang mở app")
                        .foregroundStyle(.secondary)
                        .padding(.top, 100)
                        .frame(maxWidth: .infinity)
                }
                .refreshable { await load() }
            } else {
                List(desktops, id: \.id) { desktop in
                    NavigationLink {
                        DesktopScreenView(desktopId: desktop.id, label: desktop.label)
                    } label: {
                        Label(desktop.label, systemImage: "desktopcomputer")
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Xem màn hình Desktop")
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await SignalRClient.shared.fetchConnectedDesktops()
            desktops = result.map { (id: $0.key, label: $0.value) }
            errorMessage = nil
        } catch {
            errorMessage = "Không tải được danh sách: \(error.localizedDescription)"
        }
    }
}
