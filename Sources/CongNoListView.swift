import SwiftUI
import UIKit

/// Danh sách hoá đơn còn ghi nợ, gọi GET /api/dashboard/cong-no-list (không có tham số ngày —
/// khác Hoá đơn/Thanh toán/Chi tiêu). Bấm vào card mở HoaDonDetailView để xem chi tiết + thu tiền
/// (đã bỏ 2 nút Tiền mặt/Chuyển khoản thu nhanh trên card — quay lại luồng mở sheet).
struct CongNoListView: View {
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var selectedId: String?
    @State private var searchText = ""
    @State private var copiedFeedback = false

    private var sortedItems: [HoaDonListDto] {
        items
            .filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.tenMonSummary) }
            .sorted { ($0.ngayNo ?? "") > ($1.ngayNo ?? "") }
    }

    private var totalText: String {
        HoaDonFormatting.money(sortedItems.reduce(0) { $0 + $1.conLai })
    }

    /// Nợ phát sinh hôm nay — cùng logic gộp NgayNo với sortedItems, chỉ lọc thêm theo ngày hiện tại.
    private var todayText: String {
        let today = DateNavFormat.queryDate.string(from: Date())
        let total = sortedItems
            .filter { ($0.ngayNo ?? "").hasPrefix(today) }
            .reduce(0) { $0 + $1.conLai }
        return HoaDonFormatting.money(total)
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
                                CongNoRowView(
                                    item: item,
                                    onSelect: { selectedId = item.id }
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                // Cố ý KHÔNG có nút Xoá — mọi đơn trong tab này đều đã ghi nợ, xoá
                                // cứng quá nguy hiểm (mất dữ liệu nợ khách). Chỉ cho thu tiền ở đây;
                                // nếu cần huỷ đơn thì dùng Rollback bên Desktop (NoTabControl), khớp
                                // guard NgayNo bên HoaDonTabControl.Actions.cs.
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }

                Divider()
                VStack(spacing: 2) {
                    HStack {
                        Spacer()
                        Text("Hôm nay: \(todayText)")
                            .font(.caption2).foregroundColor(.dangerColor)
                    }
                    HStack {
                        Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                        Spacer()
                        if !searchText.isEmpty {
                            Button {
                                Task { await copyBillImage() }
                            } label: {
                                Label(copiedFeedback ? "Đã copy" : "Gửi Tất Cả Bill Nợ", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.caption.bold())
                            }
                            .buttonStyle(.bordered)
                            .tint(.brandPrimary)
                            Spacer()
                        }
                        Text(totalText).font(.headline).foregroundColor(.dangerColor)
                    }
                }
                .padding()
            }
        }
        .task { await load() }
        .onEntityChanged(["HoaDon"], tab: .congNo) { Task { await load() } }
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

    /// Render toàn bộ danh sách đã lọc (kể cả phần cần cuộn) thành 1 ảnh, copy vào clipboard để dán
    /// thẳng vào khung chat Zalo/Facebook — ImageRenderer (iOS 16+) vẽ ra ngoài màn hình nên không bị
    /// giới hạn bởi viewport như chụp màn hình thường. Kèm 1 mã QR duy nhất cho TỔNG nợ đang lọc
    /// (không gắn với 1 hoá đơn cụ thể vì có thể gộp nhiều đơn) — lấy qua Backend /api/HoaDon/bill-qr,
    /// dùng chung BankQrConfig với Desktop/Mobile (xem [[project_bank_qr_consolidation]]). addInfo
    /// tính hẳn trên Backend qua /api/HoaDon/gop-addinfo (BankQrConfig.BuildAddInfo là nguồn DUY
    /// NHẤT, không còn bản build song song bằng Swift nữa — tránh lệch format như vụ thiếu "SEVQR"
    /// 2026-08-23). Chỉ ghi mã hoá đơn đầu và cuối trong danh sách đang hiển thị (mới nhất DEN cũ
    /// nhất), không liệt kê hết — tránh vượt giới hạn ký tự nội dung CK ngân hàng. `item.maHoaDon`
    /// (Backend tính sẵn) ưu tiên hơn tự cắt chuỗi id.
    private func copyBillImage() async {
        let snapshot = sortedItems
        let total = snapshot.reduce(0.0) { $0 + $1.conLai }
        let codes = snapshot.map { $0.maHoaDon?.isEmpty == false ? $0.maHoaDon! : BillTextBuilder.buildMaHoaDon($0.id) }
        let addInfo: String
        if let maDau = codes.first {
            let maCuoi = codes.last == maDau ? nil : codes.last
            addInfo = await APIClient.shared.getGopAddInfo(ten: searchText, maDau: maDau, maCuoi: maCuoi)
                ?? "SEVQR " + BillTextBuilder.toAsciiNoDiacritics("\(searchText) \(maDau)", upper: true)
        } else {
            addInfo = "SEVQR " + BillTextBuilder.toAsciiNoDiacritics(searchText, upper: true)
        }
        let qrData = await APIClient.shared.getBillQrImage(amount: total, addInfo: addInfo)
        let qrImage = qrData.flatMap { UIImage(data: $0) }

        let content = BillSnapshotView(items: snapshot, totalText: totalText, todayText: todayText, qrImage: qrImage)
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
    let todayText: String
    let qrImage: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                CongNoRowView(item: item)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            VStack(spacing: 2) {
                HStack {
                    Spacer()
                    Text("Hôm nay: \(todayText)")
                        .font(.caption2).foregroundColor(.dangerColor)
                }
                HStack {
                    Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text(totalText).font(.headline).foregroundColor(.dangerColor)
                }
            }
            .padding(12)

            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.white)
    }
}

/// Không đánh dấu private — ThongKeThangView (card "Tổng nợ hiện tại" → KhachHangNoDetailSheet) tái
/// dùng để layout khớp y hệt tab Công nợ, không phải sửa 2 nơi.
struct CongNoRowView: View {
    let item: HoaDonListDto
    /// Nil trong BillSnapshotView (ảnh render tĩnh để gửi bill — không cần tương tác).
    var onSelect: (() -> Void)? = nil
    /// false khi list đã lọc theo 1 khách (KhachHangNoDetailSheet) — tên lặp lại y hệt ở mọi dòng
    /// nên bỏ, nhường chỗ cho tóm tắt món lên làm dòng chính.
    var showName: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.dangerColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                if showName {
                    Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                        .font(.subheadline.bold())
                }
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon)
                        .font(showName ? .footnote : .subheadline.bold())
                        .foregroundColor(showName ? .textMuted : .primary)
                        .lineLimit(1)
                } else if !showName {
                    Text("Hoá đơn").font(.subheadline.bold())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(HoaDonFormatting.congNoTime(item.ngayNo))
                    .font(.footnote).foregroundColor(.textMuted)
                Text(HoaDonFormatting.money(item.conLai)).font(.subheadline.bold()).foregroundColor(.dangerColor)
            }
        }
        .padding(12)
        .background(Color.dangerColor.pastelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }
}
