import SwiftUI
import UIKit

// Màu khớp AppMobileAndroid/res/values/colors.xml (Bootstrap-style) — giữ đồng bộ hình ảnh 2 nền tảng.
extension Color {
    static let brandPrimary = Color(red: 0x0D / 255, green: 0x6E / 255, blue: 0xFD / 255)
    static let textMuted = Color(red: 0x6C / 255, green: 0x75 / 255, blue: 0x7D / 255)
    static let successColor = Color(red: 0x19 / 255, green: 0x87 / 255, blue: 0x54 / 255)
    static let dangerColor = Color(red: 0xDC / 255, green: 0x35 / 255, blue: 0x45 / 255)
    static let warningColor = Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)
    static let pinkColor = Color(red: 0xD6 / 255, green: 0x33 / 255, blue: 0x84 / 255)

    /// Trộn với trắng ra bản pastel đặc (không dùng opacity) — dùng làm nền card, giống cách Mobile
    /// web tô nền card bằng 1 màu pastel cố định thay vì border color mờ đi (opacity phụ thuộc nền
    /// phía sau, dễ ra xám/đậm khác ý muốn, nhất là dark mode).
    func pastelBackground(_ amount: CGFloat = 0.82) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func mix(_ c: CGFloat) -> CGFloat { c + (1 - c) * amount }
        return Color(red: mix(r), green: mix(g), blue: mix(b))
    }
}

enum HoaDonFormatting {
    static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.locale = Locale(identifier: "vi_VN")
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ value: Double) -> String {
        (moneyFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + " đ"
    }

    /// Viết tắt cho footer (vd "1807k") — không cần rõ số, chỉ cần ước lượng nhanh.
    static func moneyShort(_ value: Double) -> String {
        "\(Int((value / 1000).rounded()))k"
    }

    private static let isoInFormats: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"].map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    static func time(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let hm = DateFormatter()
                hm.dateFormat = "HH:mm"
                return hm.string(from: date)
            }
        }
        guard iso.count >= 16 else { return "--:--" }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(start, offsetBy: 5)
        return String(iso[start..<end])
    }

    /// Dùng cho dòng "Ghi nợ" trên tab Công nợ — chỉ cần Ngày/Tháng Giờ:Phút, không cần năm/giây.
    static func congNoTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:-- --/--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let out = DateFormatter()
                out.dateFormat = "HH:mm dd/MM"
                out.locale = Locale(identifier: "vi_VN")
                return out.string(from: date)
            }
        }
        return "--:-- --/--"
    }

    /// Số phút trôi qua từ ngayGio tới hiện tại — dùng cho badge "chờ" trên card list, xem
    /// HoaDonRowView.waitingMinutes (đóng băng tại thời điểm ghi nợ/thanh toán/đi ship nếu đã xảy ra).
    static func minutesSince(_ iso: String?, now: Date = Date()) -> Int? {
        guard let date = parseIso(iso) else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 60))
    }

    static func parseIso(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        for f in isoInFormats {
            if let date = f.date(from: iso) { return date }
        }
        return nil
    }

    /// "12 phút" nếu <1h, "1g05p" nếu >=1h.
    static func waitingText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) phút" }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)g\(String(format: "%02d", m))p"
    }

    static func phanLoaiLabel(_ phanLoai: String?) -> String {
        switch phanLoai {
        case "Tại Chỗ": return "Tại chỗ"
        case "Mv": return "Mua về"
        case "Mh": return "Mua hộ"
        case "App": return "App"
        default: return "Ship"
        }
    }

    static func phanLoaiColor(_ phanLoai: String?) -> Color {
        switch phanLoai {
        case "Tại Chỗ": return .successColor
        case "Mv": return .warningColor
        case "Mh": return .pinkColor
        case "App": return .dangerColor
        default: return .brandPrimary
        }
    }

    /// Nền tint card theo PhanLoai — dùng chính màu accent/border đã có sẵn trên card (phanLoaiColor),
    /// pha nhạt để làm nền cả card thay vì chỉ 1 thanh 4px bên trái.
    static func phanLoaiBgColor(_ phanLoai: String?) -> Color {
        phanLoaiColor(phanLoai).pastelBackground()
    }

    /// Khớp PhanLoai.NeedKhachHang (Desktop, HoaDonDomain.cs) — 3 phân loại này cần SĐT/địa chỉ giao.
    static func needKhachHang(_ phanLoai: String?) -> Bool {
        phanLoai == "Ship" || phanLoai == "Mh" || phanLoai == "App"
    }

    /// Khớp PhanLoai.HasAutoDiscount (Desktop) — App/Mua hộ tự giảm 5%, làm tròn 1000 gần nhất
    /// (PricingService.RoundToNearest1000), trừ khi người dùng đã tự sửa tay giảm giá.
    static func autoGiamGia(phanLoai: String?, tongTien: Double, manual: Bool) -> Double? {
        if manual { return nil }
        guard phanLoai == "App" || phanLoai == "Mh" else { return 0 }
        let raw = tongTien * 0.05
        let remainder = raw.truncatingRemainder(dividingBy: 1000)
        return remainder < 500 ? raw - remainder : raw + (1000 - remainder)
    }

    /// Khớp FormatDiem (Desktop, HoaDonEditWindow.KhachHang.cs) — 100 điểm raw = 1.0 hiển thị.
    static func diemDisplay(_ rawDiem: Int) -> String {
        String(format: "%.1f", Double(rawDiem) / 100.0)
    }

    /// Port y hệt HoaDonSortService.GetSortOrder (Desktop) / AppMobileAndroid HoaDonTabFragment.sortPriority.
    /// Đơn Ghi nợ rớt xuống ưu tiên thấp nhất (7) BẤT KỂ phân loại — check "isNo" phải nằm TRƯỚC nhánh
    /// Ship-chưa-gán-shipper, sai thứ tự if/else ở đây từng khiến kết quả sai.
    static func sortPriority(_ item: HoaDonListDto) -> Int {
        let phanLoai = item.phanLoai
        let conLai = item.conLai
        let chuaCoShipper = phanLoai == "Ship" && (item.nguoiShip?.isEmpty ?? true)
        let isNo = !(item.ngayNo?.isEmpty ?? true)

        if conLai <= 0.0 && phanLoai == "Ship" && chuaCoShipper { return 1 }
        if conLai <= 0.0 { return 6 }
        if isNo { return 7 }
        if phanLoai == "Ship" && chuaCoShipper { return 1 }
        if phanLoai == "Ship" { return 5 }
        if phanLoai == "Mv" || phanLoai == "Mh" { return 2 }
        if phanLoai == "App" { return 3 }
        return 4 // Tại Chỗ
    }
}
