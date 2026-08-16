import SwiftUI

// Tách từ HoaDonListView để tái dùng cho các tab theo ngày/tháng khác (Thanh toán, Chi tiêu,
// 7 trang báo cáo) — khớp DateNavHelper.kt bên AppMobileAndroid.

enum DateNavFormat {
    static let queryDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f
    }()
}

struct DayNavBar: View {
    @Binding var date: Date
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button { showPicker = true } label: {
                Text(DateNavFormat.dayTitle.string(from: date)).font(.headline)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn ngày", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") {
                                showPicker = false
                                onChange()
                            }
                        }
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }

    private func change(_ delta: Int) {
        date = Calendar.current.date(byAdding: .day, value: delta, to: date) ?? date
        onChange()
    }
}

struct MonthNavBar: View {
    @Binding var year: Int
    @Binding var month: Int
    var onChange: () -> Void
    @State private var showPicker = false
    @State private var pickerDate = Date()

    private var titleText: String {
        String(format: "%02d/%d", month, year)
    }

    var body: some View {
        HStack {
            Button { change(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Button {
                var comps = DateComponents()
                comps.year = year; comps.month = month; comps.day = 1
                pickerDate = Calendar.current.date(from: comps) ?? Date()
                showPicker = true
            } label: {
                Text(titleText).font(.headline)
            }
            .buttonStyle(.plain)
            Spacer()
            Button { change(1) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn tháng", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") {
                                let cal = Calendar.current
                                year = cal.component(.year, from: pickerDate)
                                month = cal.component(.month, from: pickerDate)
                                showPicker = false
                                onChange()
                            }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
    }

    private func change(_ delta: Int) {
        month += delta
        if month < 1 { month = 12; year -= 1 }
        if month > 12 { month = 1; year += 1 }
        onChange()
    }
}
