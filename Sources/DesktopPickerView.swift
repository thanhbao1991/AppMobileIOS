import SwiftUI

/// Tự vào thẳng máy Desktop client (TraSuaApp.Desktop) xếp cuối danh sách (sort theo tên máy) —
/// không cần chọn tay. Nếu chưa tải xong/không có máy nào thì hiện trạng thái tương ứng.
struct DesktopPickerView: View {
    @State private var target: (id: String, label: String)?
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let target {
                DesktopScreenView(desktopId: target.id, label: target.label)
            } else if loading {
                ProgressView()
            } else {
                VStack(spacing: 12) {
                    Text(errorMessage ?? "Không có máy nào đang mở app")
                        .foregroundStyle(.secondary)
                    Button("Thử lại") { Task { await load() } }
                }
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
            target = result.map { ($0.key, $0.value) }.sorted { $0.label < $1.label }.last
            errorMessage = nil
        } catch {
            errorMessage = "Không tải được danh sách: \(error.localizedDescription)"
        }
    }
}
