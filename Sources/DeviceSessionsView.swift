import SwiftUI

/// Danh sách thiết bị đang đăng nhập tài khoản hiện tại — giống trang "Tài khoản Apple" của iOS.
/// GET/DELETE /api/Auth/sessions. Chỉ có ở đây (không có trên Desktop/Android) — iOS là nơi duy nhất
/// xem/gỡ thiết bị, dù các phiên của Desktop/Android cũng hiện trong danh sách này.
struct DeviceSessionsView: View {
    @State private var sessions: [PhienDangNhapDto] = []
    @State private var loading = false
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !hasLoaded {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if sessions.isEmpty {
                VStack { Spacer(); Text("Không có thiết bị nào").foregroundColor(.textMuted); Spacer() }
            } else {
                List {
                    ForEach(sessions) { session in
                        SessionRowView(session: session)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await revoke(session) }
                                } label: {
                                    Label("Gỡ", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Thiết bị đăng nhập")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        sessions = await APIClient.shared.getSessions()
        loading = false
        hasLoaded = true
    }

    private func revoke(_ session: PhienDangNhapDto) async {
        let result = await APIClient.shared.revokeSession(id: session.id)
        if result.success {
            sessions.removeAll { $0.id == session.id }
        }
    }
}

private struct SessionRowView: View {
    let session: PhienDangNhapDto

    var body: some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundColor(.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.thietBi?.isEmpty == false ? session.thietBi! : "Thiết bị không tên")
                        .font(.subheadline).fontWeight(.medium)
                    if session.laThietBiHienTai {
                        Text("Thiết bị này")
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.successColor)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                Text("Đăng nhập: \(HoaDonFormatting.congNoTime(session.ngayTao))")
                    .font(.caption2).foregroundColor(.textMuted)
                Text("Hết hạn: \(HoaDonFormatting.congNoTime(session.hetHan))")
                    .font(.caption2).foregroundColor(.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
