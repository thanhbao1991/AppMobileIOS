import SwiftUI

/// Danh sách Desktop client (TraSuaApp.Desktop) đang mở, tự đăng ký qua hub "/hub/entity"
/// (RegisterAsDesktop). Chọn 1 máy để xem — xem `DesktopScreenView`.
struct DesktopPickerView: View {
    @State private var desktops: [(id: String, label: String)] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if loading && desktops.isEmpty {
                ProgressView()
            } else if desktops.isEmpty {
                Text(errorMessage ?? "Không có máy nào đang mở app")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(desktops, id: \.id) { desktop in
                    NavigationLink {
                        DesktopScreenView(desktopId: desktop.id, label: desktop.label)
                    } label: {
                        Label(desktop.label, systemImage: "desktopcomputer")
                    }
                }
            }
        }
        .navigationTitle("Xem màn hình Desktop")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await SignalRClient.shared.fetchConnectedDesktops()
            desktops = result.map { ($0.key, $0.value) }.sorted { $0.label < $1.label }
            errorMessage = nil
        } catch {
            errorMessage = "Không tải được danh sách: \(error.localizedDescription)"
        }
    }
}
