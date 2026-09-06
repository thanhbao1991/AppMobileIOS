import XCTest
@testable import AppMobileIOS

/// HoaDonFormatting.sortPriority/phanLoaiLabel/needKhachHang là bản PORT tay từ Desktop
/// (HoaDonSortService.GetSortOrder / HoaDonDomain.cs) — dự án đã có tiền lệ port sai thứ tự if/else
/// gây bug thật (xem comment trong HoaDonFormatting.swift, mirror đúng lỗi ở AppMobileAndroid). Test
/// này khoá lại từng nhánh để lần port tiếp theo (nếu Desktop đổi logic) không lặp lại sai sót cũ.
final class HoaDonFormattingTests: XCTestCase {

    // MARK: - money / moneyShort

    func test_money_dinhDangKieuVietNamCoDauCham() {
        XCTAssertEqual(HoaDonFormatting.money(1_500_000), "1.500.000 đ")
        XCTAssertEqual(HoaDonFormatting.money(0), "0 đ")
    }

    func test_moneyShort_lamTronVeNghin() {
        XCTAssertEqual(HoaDonFormatting.moneyShort(1_807_400), "1807k")
        XCTAssertEqual(HoaDonFormatting.moneyShort(999), "1k")
    }

    // MARK: - time / congNoTime / minutesSince

    func test_time_parseDungDinhDangISOKhongMili() {
        XCTAssertEqual(HoaDonFormatting.time("2026-09-06T14:05:00"), "14:05")
    }

    func test_time_parseDungDinhDangISOCoMili() {
        XCTAssertEqual(HoaDonFormatting.time("2026-09-06T14:05:00.123"), "14:05")
    }

    func test_time_chuoiRongHoacNilTraVeMacDinh() {
        XCTAssertEqual(HoaDonFormatting.time(nil), "--:--")
        XCTAssertEqual(HoaDonFormatting.time(""), "--:--")
    }

    func test_congNoTime_gomCaNgayThang() {
        XCTAssertEqual(HoaDonFormatting.congNoTime("2026-09-06T14:05:00"), "14:05 06/09")
    }

    func test_minutesSince_tinhDungSoPhutTroiQua() {
        let ngayGio = "2026-09-06T14:00:00"
        let now = HoaDonFormatting.parseIso(ngayGio)!.addingTimeInterval(15 * 60)
        XCTAssertEqual(HoaDonFormatting.minutesSince(ngayGio, now: now), 15)
    }

    func test_minutesSince_isoKhongParseDuocTraVeNil() {
        XCTAssertNil(HoaDonFormatting.minutesSince("không phải ISO"))
    }

    // MARK: - waitingText

    func test_waitingText_duoi1GioChiHienPhut() {
        XCTAssertEqual(HoaDonFormatting.waitingText(45), "45 phút")
    }

    func test_waitingText_tu1GioTroLenHienGioPhut() {
        XCTAssertEqual(HoaDonFormatting.waitingText(65), "1g05p")
        XCTAssertEqual(HoaDonFormatting.waitingText(125), "2g05p")
    }

    // MARK: - phanLoaiLabel

    func test_phanLoaiLabel_khopTungPhanLoai() {
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("Tại Chỗ"), "Tại chỗ")
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("Mv"), "Mua về")
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("Mh"), "Mua hộ")
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("App"), "App")
    }

    // AppDatHang (thêm 2026-09-06) PHẢI có label riêng "App Khách" — rơi vào default sẽ hiện SAI
    // thành "Ship", đúng lớp bug đã tìm thấy ở Desktop HoaDonTabControl.xaml.
    func test_phanLoaiLabel_appDatHang_KHONG_duocRoiVaoDefaultShip() {
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("AppDatHang"), "App Khách")
    }

    func test_phanLoaiLabel_khongXacDinhMacDinhLaShip() {
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel("Ship"), "Ship")
        XCTAssertEqual(HoaDonFormatting.phanLoaiLabel(nil), "Ship")
    }

    // MARK: - needKhachHang

    func test_needKhachHang_4PhanLoaiCanThongTinGiao() {
        for pl in ["Ship", "Mh", "App", "AppDatHang"] {
            XCTAssertTrue(HoaDonFormatting.needKhachHang(pl), "\(pl) phải cần SĐT/địa chỉ")
        }
    }

    func test_needKhachHang_TaiChoVaMvKhongCan() {
        XCTAssertFalse(HoaDonFormatting.needKhachHang("Tại Chỗ"))
        XCTAssertFalse(HoaDonFormatting.needKhachHang("Mv"))
    }

    // MARK: - autoGiamGia

    func test_autoGiamGia_manualThiKhongTuGiam() {
        XCTAssertNil(HoaDonFormatting.autoGiamGia(phanLoai: "App", tongTien: 100_000, manual: true))
    }

    func test_autoGiamGia_phanLoaiKhongApDungTraVe0() {
        XCTAssertEqual(HoaDonFormatting.autoGiamGia(phanLoai: "Tại Chỗ", tongTien: 100_000, manual: false), 0)
    }

    func test_autoGiamGia_AppVaMh_giam5PhanTramLamTron1000() {
        // 100.000 * 5% = 5.000 — đã tròn 1000 sẵn, không đổi.
        XCTAssertEqual(HoaDonFormatting.autoGiamGia(phanLoai: "App", tongTien: 100_000, manual: false), 5_000)
        // 123.000 * 5% = 6.150 — dư 150 (<500) nên làm tròn XUỐNG 6.000.
        XCTAssertEqual(HoaDonFormatting.autoGiamGia(phanLoai: "Mh", tongTien: 123_000, manual: false), 6_000)
        // 137.000 * 5% = 6.850 — dư 850 (>=500) nên làm tròn LÊN 7.000.
        XCTAssertEqual(HoaDonFormatting.autoGiamGia(phanLoai: "App", tongTien: 137_000, manual: false), 7_000)
    }

    // MARK: - diemDisplay

    func test_diemDisplay_100RawBang1Diem() {
        XCTAssertEqual(HoaDonFormatting.diemDisplay(250), "2.5")
        XCTAssertEqual(HoaDonFormatting.diemDisplay(0), "0.0")
    }

    // MARK: - sortPriority (port từ HoaDonSortService.GetSortOrder)

    private func hoaDon(
        phanLoai: String?,
        conLai: Double = 50_000,
        nguoiShip: String? = nil,
        ngayNo: String? = nil
    ) -> HoaDonListDto {
        HoaDonListDto(
            id: "1", khachHangId: nil, tenKhachHangText: nil, tenBan: nil,
            phanLoai: phanLoai, ngayGio: nil, lastModified: nil, ngayShip: nil,
            ngayNo: ngayNo, ngayIn: nil, ngayThanhToan: nil, nguoiShip: nguoiShip,
            ghiChu: nil, ghiChuShipper: nil, diaChiText: nil, soDienThoaiText: nil,
            isBank: nil, isAutoBank: nil, thanhTien: 50_000, conLai: conLai,
            tenMonSummary: nil, maHoaDon: "HD00000001"
        )
    }

    func test_sortPriority_ShipChuaGanShipperUuTienCaoNhat() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Ship", nguoiShip: nil)), 1)
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Ship", nguoiShip: "")), 1)
    }

    // Bug đã tìm thấy ở Desktop (HoaDonSortService) và port sai lần đầu ở Android: AppDatHang phải
    // CÙNG mức ưu tiên với Ship khi chưa gán shipper, không được rớt xuống mức 4 (Tại Chỗ).
    func test_sortPriority_AppDatHangChuaGanShipper_CungMucUuTienVoiShip() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "AppDatHang", nguoiShip: nil)), 1)
    }

    // Ghi nợ rớt xuống ưu tiên thấp nhất BẤT KỂ phân loại — kể cả đơn Ship chưa gán shipper.
    func test_sortPriority_GhiNo_LuonUuTienThapNhat_KeCaDonShipChuaGanShipper() {
        let don = hoaDon(phanLoai: "Ship", conLai: 50_000, nguoiShip: nil, ngayNo: "2026-09-06T10:00:00")
        XCTAssertEqual(HoaDonFormatting.sortPriority(don), 7)
    }

    func test_sortPriority_DaThanhToanHet() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Tại Chỗ", conLai: 0)), 6)
    }

    func test_sortPriority_ShipDaGanShipper() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Ship", nguoiShip: "Shipper A")), 5)
    }

    func test_sortPriority_MvMh() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Mv")), 2)
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Mh")), 2)
    }

    func test_sortPriority_App() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "App")), 3)
    }

    func test_sortPriority_TaiCho_MacDinhThapNhatTrongCacDonChuaThanhToan() {
        XCTAssertEqual(HoaDonFormatting.sortPriority(hoaDon(phanLoai: "Tại Chỗ")), 4)
    }
}
