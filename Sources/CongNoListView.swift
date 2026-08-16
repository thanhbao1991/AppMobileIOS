import SwiftUI
import UIKit

/// Danh sách hoá đơn còn ghi nợ, gọi GET /api/dashboard/cong-no-list (không có tham số ngày —
/// khác Hoá đơn/Thanh toán/Chi tiêu). Bấm vào mở lại HoaDonDetailView để xem chi tiết; vuốt phải
/// (leading) có 3 nút thu nhanh Tiền mặt/Chuyển khoản/Xoá không cần mở sheet.
struct CongNoListView: View {
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var selectedId: String?
    @State private var searchText = ""
    @State private var busyId: String?
    @State private var copiedFeedback = false

    private var sortedItems: [HoaDonListDto] {
        items
            .filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.tenMonSummary) }
            .sorted { ($0.ngayNo ?? "") > ($1.ngayNo ?? "") }
    }

    private var totalText: String {
        HoaDonFormatting.money(sortedItems.reduce(0) { $0 + $1.conLai })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm khách, món, ghi chú...")

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if sortedItems.isEmpty {
                            Text("Không có công nợ nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(sortedItems) { item in
                                CongNoRowView(item: item, busy: busyId == item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedId = item.id }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            Task { await thu(item, isCash: true) }
                                        } label: {
                                            Label("Tiền mặt", systemImage: "banknote")
                                        }
                                        .tint(.successColor)
                                        Button {
                                            Task { await thu(item, isCash: false) }
                                        } label: {
                                            Label("Chuyển khoản", systemImage: "creditcard")
                                        }
                                        .tint(.brandPrimary)
                                        Button(role: .destructive) {
                                            Task { await xoa(item) }
                                        } label: {
                                            Label("Xoá", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                HStack {
                    Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    if !searchText.isEmpty {
                        Button {
                            copyBillImage()
                        } label: {
                            Label(copiedFeedback ? "Đã copy" : "Gửi Bill Nợ", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        .tint(.brandPrimary)
                        Spacer()
                    }
                    Text(totalText).font(.headline).foregroundColor(.dangerColor)
                }
                .padding()
            }
        }
        .task { await load() }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongNoList()
        loading = false
        hasLoaded = true
    }

    private func thu(_ item: HoaDonListDto, isCash: Bool) async {
        busyId = item.id
        let result = await APIClient.shared.thuTien(
            hoaDonId: item.id, isCash: isCash, soTien: item.conLai,
            ten: item.tenKhachHangText ?? "Khách lẻ", khachHangId: item.khachHangId
        )
        busyId = nil
        if result.success {
            await load()
        }
    }

    private func xoa(_ item: HoaDonListDto) async {
        busyId = item.id
        let result = await APIClient.shared.delete(hoaDonId: item.id)
        busyId = nil
        if result.success {
            items.removeAll { $0.id == item.id }
        }
    }

    /// Render toàn bộ danh sách đã lọc (kể cả phần cần cuộn) thành 1 ảnh, copy vào clipboard để dán
    /// thẳng vào khung chat Zalo/Facebook — ImageRenderer (iOS 16+) vẽ ra ngoài màn hình nên không bị
    /// giới hạn bởi viewport như chụp màn hình thường.
    private func copyBillImage() {
        let snapshot = sortedItems
        let content = BillSnapshotView(items: snapshot, totalText: totalText)
            .frame(width: UIScreen.main.bounds.width)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        guard let uiImage = renderer.uiImage else { return }
        UIPasteboard.general.image = uiImage

        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedFeedback = false
        }
    }
}

/// Layout dùng riêng để render ảnh Gửi Bill Nợ — độc lập với List (List không rasterize hết nội
/// dung ngoài viewport), nền trắng cố định để ảnh dán vào chat luôn đọc được bất kể theme máy.
private struct BillSnapshotView: View {
    let items: [HoaDonListDto]
    let totalText: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                CongNoRowView(item: item, busy: false)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            HStack {
                Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                Spacer()
                Text(totalText).font(.headline).foregroundColor(.dangerColor)
            }
            .padding(12)
        }
        .background(Color.white)
    }
}

private struct CongNoRowView: View {
    let item: HoaDonListDto
    let busy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.dangerColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                        .font(.subheadline.bold())
                    Text(HoaDonFormatting.congNoTime(item.ngayNo))
                        .font(.footnote).foregroundColor(.textMuted)
                }
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                Text(HoaDonFormatting.money(item.conLai)).font(.subheadline.bold()).foregroundColor(.dangerColor)
            }
        }
    }
}
