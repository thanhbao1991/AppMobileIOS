import SwiftUI

/// Sheet chi tiết 1 dòng thanh toán — thay cho vuốt trái để xoá (dễ bấm nhầm). Khớp cách
/// HoaDonDetailView hiện info + action buttons, luôn có confirm trước khi đổi phương thức/xoá vì
/// đụng tiền thật.
struct ThanhToanDetailView: View {
    let item: ChiTietHoaDonThanhToanDto
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var errorText: String?
    @State private var showDoiPhuongThucConfirm = false
    @State private var showDeleteConfirm = false

    private var isBank: Bool {
        item.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let errorText {
                        Text(errorText).foregroundColor(.dangerColor).font(.footnote)
                    }

                    infoRow("Khách hàng", item.ten)
                    infoRow("Thời gian", HoaDonFormatting.congNoTime(item.ngayGio))
                    if let loai = item.loaiThanhToan, !loai.isEmpty { infoRow("Loại", loai) }
                    if let mon = item.tenMonSummary, !mon.isEmpty { infoRow("Món", mon) }
                    if let gc = item.ghiChu, !gc.isEmpty { infoRow("Ghi chú", gc) }
                    infoRow("Phương thức", isBank ? "Chuyển khoản" : "Tiền mặt")

                    HStack {
                        Text("Số tiền").foregroundColor(.textMuted)
                        Spacer()
                        Text(HoaDonFormatting.money(item.soTien))
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)

                    Divider()

                    VStack(spacing: 10) {
                        ActionButtonView(
                            icon: "arrow.left.arrow.right", code: nil,
                            caption: isBank ? "Đổi sang Tiền mặt" : "Đổi sang Chuyển khoản",
                            color: isBank ? .successColor : .brandPrimary
                        ) {
                            showDoiPhuongThucConfirm = true
                        }

                        ActionButtonView(icon: "trash", code: nil, caption: "Xoá", color: .dangerColor) {
                            showDeleteConfirm = true
                        }
                    }
                }
                .padding()
            }
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .navigationTitle("Chi tiết thanh toán")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .confirmationDialog(
                "Đổi phương thức sang \(isBank ? "Tiền mặt" : "Chuyển khoản")?",
                isPresented: $showDoiPhuongThucConfirm, titleVisibility: .visible
            ) {
                Button("Xác nhận") { Task { await doiPhuongThuc() } }
                Button("Huỷ", role: .cancel) {}
            }
            .confirmationDialog(
                "Xoá dòng thanh toán \(HoaDonFormatting.money(item.soTien)) của \(item.ten)?",
                isPresented: $showDeleteConfirm, titleVisibility: .visible
            ) {
                Button("Xoá", role: .destructive) { Task { await delete() } }
                Button("Huỷ", role: .cancel) {}
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.textMuted)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func doiPhuongThuc() async {
        await run { await APIClient.shared.doiPhuongThucThanhToan(id: item.id) }
    }

    private func delete() async {
        await run { await APIClient.shared.deleteThanhToan(id: item.id) }
    }

    private func run(_ action: () async -> ActionResult) async {
        busy = true
        let result = await action()
        busy = false
        if result.success {
            onChanged()
            dismiss()
        } else {
            errorText = result.message ?? "Thao tác thất bại."
        }
    }
}
