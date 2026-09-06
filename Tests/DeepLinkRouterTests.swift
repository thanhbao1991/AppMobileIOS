import XCTest
@testable import AppMobileIOS

/// DeepLinkRouter xử lý link "trasuaapp://khachhang/{id}" ContactSyncService ghi vào Danh bạ — nhân
/// viên bấm từ Recents sau khi cúp máy để mở thẳng form tạo đơn Ship, prefill đúng khách vừa gọi.
/// Sai 1 trong 3 điều kiện (scheme/host/id) là link bấm từ Danh bạ không mở đúng màn hình, hoặc mở
/// nhầm khách.
@MainActor
final class DeepLinkRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DeepLinkRouter.shared.khachHangIdToOrder = nil
    }

    func test_handle_urlHopLe_setDungKhachHangId() {
        let url = URL(string: "trasuaapp://khachhang/abc-123")!

        DeepLinkRouter.shared.handle(url)

        XCTAssertEqual(DeepLinkRouter.shared.khachHangIdToOrder, "abc-123")
    }

    func test_handle_saiScheme_bosQua() {
        let url = URL(string: "https://khachhang/abc-123")!

        DeepLinkRouter.shared.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.khachHangIdToOrder)
    }

    func test_handle_saiHost_bosQua() {
        let url = URL(string: "trasuaapp://sanpham/abc-123")!

        DeepLinkRouter.shared.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.khachHangIdToOrder)
    }

    func test_handle_thieuId_bosQua() {
        let url = URL(string: "trasuaapp://khachhang/")!

        DeepLinkRouter.shared.handle(url)

        XCTAssertNil(DeepLinkRouter.shared.khachHangIdToOrder)
    }
}
