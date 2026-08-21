import SwiftUI

/// Tự vào thẳng máy Desktop client (TraSuaApp.Desktop) có tên cố định `targetMachineName` —
/// xác định bởi ĐÚNG TÊN MÁY (khớp `Environment.MachineName` phía Desktop), không phải theo vị
/// trí/thứ tự trong danh sách (danh sách có thể đổi khi thêm/bớt máy khác). Không cần chọn tay.
struct DesktopPickerView: View {
    private let targetMachineName = "DESKTOP-118TMVD"

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
                    Text(errorMessage ?? "Không tìm thấy máy \"\(targetMachineName)\" đang mở app")
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
            if let match = result.first(where: { $0.value == targetMachineName }) {
                target = (match.key, match.value)
            }
            errorMessage = nil
        } catch {
            errorMessage = "Không tải được danh sách: \(error.localizedDescription)"
        }
    }
}
