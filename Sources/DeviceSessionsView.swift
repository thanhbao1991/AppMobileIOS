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

    // Icon + nhãn theo nền tảng — phân biệt rõ máy tính/điện thoại, không chỉ dựa vào ThietBi tự do
    // (dễ trùng/gây nhầm với tên tài khoản, ví dụ user đặt tên máy trùng "ADMIN").
    private var platformIcon: String {
        switch session.nenTang {
        case "Desktop": return "desktopcomputer"
        case "Android": return "phone.fill"
        case "iOS": return "iphone"
        default: return "questionmark.circle"
        }
    }

    private var platformLabel: String? {
        switch session.nenTang {
        case "Desktop": return "Máy tính"
        case "Android": return "Android"
        case "iOS": return "iPhone"
        default: return nil
        }
    }

    var body: some View {
        HStack {
            Image(systemName: platformIcon)
                .foregroundColor(.brandPrimary)
                .frame(width: 22)
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
                HStack(spacing: 4) {
                    if let platformLabel {
                        Text(platformLabel).font(.caption2).foregroundColor(.brandPrimary)
                    }
                    // Chỉ có giá trị khi người xem là "admin" — xem được session của mọi tài khoản.
                    if let tk = session.tenTaiKhoan, !tk.isEmpty {
                        Text("· \(tk)").font(.caption2).foregroundColor(.textMuted)
                    }
                }
                Text("Đăng nhập: \(DeviceSessionsView.formatUtc(session.ngayTao))")
                    .font(.caption2).foregroundColor(.textMuted)
                Text("Hết hạn: \(DeviceSessionsView.formatUtc(session.hetHan))")
                    .font(.caption2).foregroundColor(.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

extension DeviceSessionsView {
    // Backend trả DateTime dạng "yyyy-MM-ddTHH:mm:ss.fffffff" (Kind=Unspecified nhưng thực chất là
    // UTC) — KHÔNG dùng HoaDonFormatting.congNoTime vì formatter đó không set timeZone khi parse,
    // đọc nhầm giờ UTC thành giờ máy (lệch 7h so với giờ VN thật). Cắt phần fractional-second (thừa
    // hơn .SSS mà DateFormatter chuẩn hỗ trợ) rồi parse tường minh với timeZone UTC, xuất ra theo
    // giờ máy hiện tại.
    static func formatUtc(_ iso: String) -> String {
        let base = String(iso.prefix(19)) // "yyyy-MM-ddTHH:mm:ss"
        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        inFormatter.locale = Locale(identifier: "en_US_POSIX")
        inFormatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = inFormatter.date(from: base) else { return "--:-- --/--" }

        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "HH:mm dd/MM"
        outFormatter.locale = Locale(identifier: "vi_VN")
        return outFormatter.string(from: date)
    }
}
