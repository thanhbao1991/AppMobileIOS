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

    /// Chỉ Ngày/Tháng, bỏ năm — theo yêu cầu rút gọn UI (năm không cần thiết cho việc chọn nhanh).
    static let dayTitle: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM"
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

/// Gộp chọn ngày + ô tìm kiếm chung 1 dòng — thay cho DayNavBar+SearchBar 2 dòng riêng, bỏ hẳn 2 nút
/// chevron điều hướng (chỉ còn bấm vào ngày để mở DatePicker).
struct DaySearchBar: View {
    @Binding var date: Date
    @Binding var searchText: String
    var placeholder: String = "Tìm..."
    /// Nút phụ (vd "+") đặt bên trái cùng, trước nút ngày — tìm kiếm vẫn luôn ở giữa.
    var leading: AnyView? = nil
    /// Nút phụ (vd icon lọc nhanh) đặt bên phải cùng, sau ô tìm kiếm.
    var trailing: AnyView? = nil
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 8) {
            if let leading { leading }

            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(DateNavFormat.dayTitle.string(from: date))
                }
                .font(.subheadline.bold())
                .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.plain)
            .fixedSize()

            SearchFieldRow(text: $searchText, placeholder: placeholder)

            if let trailing { trailing }
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
                    // Chọn ngày (tap vào 1 ô) là đóng luôn, không cần bấm "Xong" nữa — chỉ đổi
                    // tháng/năm hiển thị trong lịch không kích hoạt vì chưa đổi giá trị `date`.
                    .onChange(of: date) { _ in
                        showPicker = false
                        onChange()
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }
}

/// Chỉ chọn ngày, không search — dùng cho trang không có ô tìm kiếm (vd ThongKeView). Canh trái
/// giống hệt nút ngày trong DaySearchBar (tab Hoá đơn) để vị trí khớp nhau giữa các tab.
struct DayDateBar: View {
    @Binding var date: Date
    /// Nút phụ (vd link "Thống kê tháng") đặt bên phải cùng — khớp pattern `trailing` của DaySearchBar.
    /// Khai báo TRƯỚC onChange vì onChange truyền qua trailing-closure ở call site (phải là param cuối).
    var trailing: AnyView? = nil
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack {
            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(DateNavFormat.dayTitle.string(from: date))
                }
                .font(.subheadline.bold())
                .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.plain)
            .fixedSize()

            Spacer()

            if let trailing { trailing }
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
                    .onChange(of: date) { _ in
                        showPicker = false
                        onChange()
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }
}

/// Chỉ chọn tháng/năm, không search — dùng cho ThongKeThangView. `DatePicker` chuẩn của iOS không
/// có chế độ "chỉ tháng/năm" nên tự ghép 2 bánh xe Picker trong sheet riêng (MonthYearPickerSheet),
/// cộng 2 nút chevron để nhảy nhanh tháng trước/sau mà không cần mở sheet.
struct MonthDateBar: View {
    @Binding var date: Date
    var onChange: () -> Void
    @State private var showPicker = false

    var body: some View {
        HStack(spacing: 4) {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundColor(.brandPrimary)

            Button { showPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(DateNavFormat.monthTitle.string(from: date))
                }
                .font(.subheadline.bold())
                .foregroundColor(.brandPrimary)
            }
            .buttonStyle(.plain)
            .fixedSize()

            Button { shift(1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundColor(.brandPrimary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            MonthYearPickerSheet(date: $date) {
                showPicker = false
                onChange()
            }
            .presentationDetents([.height(260)])
        }
    }

    private func shift(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: delta, to: date) {
            date = newDate
            onChange()
        }
    }
}

private struct MonthYearPickerSheet: View {
    @Binding var date: Date
    var onDone: () -> Void

    @State private var month: Int
    @State private var year: Int

    private static let months = Array(1...12)
    private let years: [Int]

    init(date: Binding<Date>, onDone: @escaping () -> Void) {
        self._date = date
        self.onDone = onDone
        let cal = Calendar.current
        _month = State(initialValue: cal.component(.month, from: date.wrappedValue))
        _year = State(initialValue: cal.component(.year, from: date.wrappedValue))
        let currentYear = cal.component(.year, from: Date())
        years = Array((currentYear - 5)...(currentYear + 1))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Tháng", selection: $month) {
                    ForEach(Self.months, id: \.self) { m in
                        Text("Tháng \(m)").tag(m)
                    }
                }
                .pickerStyle(.wheel)

                Picker("Năm", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        if let newDate = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) {
                            date = newDate
                        }
                        onDone()
                    }
                }
            }
        }
    }
}
