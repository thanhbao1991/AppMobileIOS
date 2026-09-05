import SwiftUI

/// Chỉnh ngưỡng/số tiền các tính năng giữ chân khách trong app khách (AppDatHangIOS) — Ly Bí Mật,
/// giới thiệu bạn bè, sinh nhật, vòng quay may mắn, thẻ sưu tập ly. GET/PUT api/GamificationConfig.
struct GamificationConfigView: View {
    @State private var config: GamificationConfigDto?
    @State private var hasLoaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        Group {
            if !hasLoaded {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if var cfg = config {
                Form {
                    Section("Ly Bí Mật 🎁") {
                        moneyRow("Giá khách trả", value: Binding(
                            get: { cfg.lyBiMatGiaTraTien },
                            set: { cfg.lyBiMatGiaTraTien = $0; config = cfg }
                        ))
                        moneyRow("Ngưỡng giá thật tối đa", value: Binding(
                            get: { cfg.lyBiMatNguongGiaThat },
                            set: { cfg.lyBiMatNguongGiaThat = $0; config = cfg }
                        ))
                    } footer: {
                        Text("Chỉ món có giá thật ≤ ngưỡng mới được đưa vào bốc ngẫu nhiên.")
                    }

                    Section("Giới thiệu bạn bè 👥") {
                        moneyRow("Thưởng mỗi bên", value: Binding(
                            get: { cfg.gioiThieuThuong },
                            set: { cfg.gioiThieuThuong = $0; config = cfg }
                        ))
                    } footer: {
                        Text("Cả người giới thiệu và người được giới thiệu đều nhận số tiền này vào ví.")
                    }

                    Section("Sinh nhật 🎂") {
                        moneyRow("Quà sinh nhật (1 lần/năm)", value: Binding(
                            get: { cfg.sinhNhatThuong },
                            set: { cfg.sinhNhatThuong = $0; config = cfg }
                        ))
                    }

                    Section("Thẻ sưu tập ly 🧋") {
                        HStack {
                            Text("Số đơn / lần đổi thưởng")
                            Spacer()
                            TextField("10", value: Binding(
                                get: { cfg.stampMocThuong },
                                set: { cfg.stampMocThuong = $0; config = cfg }
                            ), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }

                    Section {
                        ForEach(Array(cfg.vongQuayPhanThuong.enumerated()), id: \.element.id) { idx, item in
                            VongQuayRowEditor(
                                item: Binding(
                                    get: { cfg.vongQuayPhanThuong[idx] },
                                    set: { cfg.vongQuayPhanThuong[idx] = $0; config = cfg }
                                ),
                                phanTramText: phanTram(item, in: cfg.vongQuayPhanThuong)
                            )
                        }
                        .onDelete { offsets in
                            cfg.vongQuayPhanThuong.remove(atOffsets: offsets)
                            config = cfg
                        }

                        Button {
                            cfg.vongQuayPhanThuong.append(VongQuayPhanThuongDto(label: "Ô thưởng mới", trongSo: 10, thuong: 0))
                            config = cfg
                        } label: {
                            Label("Thêm ô thưởng", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Vòng quay may mắn 🎡")
                    } footer: {
                        Text("Trọng số càng cao thì % trúng càng lớn. Tiền thưởng = 0 nghĩa là \"không trúng\".")
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundColor(.dangerColor)
                    }
                    if let savedMessage {
                        Text(savedMessage).foregroundColor(.successColor)
                    }
                }
                .tint(.brandPrimary)
            }
        }
        .navigationTitle("Cấu hình Ưu đãi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(saving ? "Đang lưu..." : "Lưu") {
                    Task { await save() }
                }
                .disabled(saving || config == nil)
            }
        }
        .task { await load() }
    }

    private func moneyRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("đ").foregroundColor(.textMuted)
        }
    }

    private func phanTram(_ item: VongQuayPhanThuongDto, in list: [VongQuayPhanThuongDto]) -> String {
        let tong = list.reduce(0) { $0 + $1.trongSo }
        guard tong > 0 else { return "0%" }
        let pct = Double(item.trongSo) / Double(tong) * 100
        return String(format: "%.0f%%", pct)
    }

    private func load() async {
        config = await APIClient.shared.getGamificationConfig()
        hasLoaded = true
    }

    private func save() async {
        guard let cfg = config else { return }
        saving = true
        errorMessage = nil
        savedMessage = nil
        let result = await APIClient.shared.updateGamificationConfig(cfg)
        saving = false
        if result.success {
            savedMessage = result.message ?? "Đã lưu."
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}

private struct VongQuayRowEditor: View {
    @Binding var item: VongQuayPhanThuongDto
    let phanTramText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nhãn hiển thị", text: $item.label)
                .font(.subheadline).fontWeight(.semibold)
            HStack {
                Stepper("Trọng số: \(item.trongSo) (\(phanTramText))", value: $item.trongSo, in: 1...1000)
            }
            .font(.caption)
            HStack {
                Text("Tiền thưởng")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Spacer()
                TextField("0", value: $item.thuong, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("đ").font(.caption).foregroundColor(.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
