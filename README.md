# AppMobileIOS

App **native thật** (SwiftUI, không phải WebView bọc web) cho ĐENN — gọi thẳng
`TraSuaApp.Backend` API. Tất cả tính năng dưới đây đều nối API thật (khác `AppMobileAndroid` — bản
Android hiện vẫn còn sample data ở nhiều tab, iOS đã vượt qua port 1:1 để gọi API thật luôn). Tất
cả tab danh sách đều có ô tìm kiếm client-side (lọc tên khách/món/ghi chú — khớp hành vi search
trên `TraSuaApp.Mobile` web cũ).

Thanh tab chỉ có **5 mục** — 4 tab dùng hàng ngày + 1 tab "Thêm" gom phần còn lại (menu, không phải
`TabView` tự động dồn — kiểm soát rõ ràng mục nào lộ ra ngoài):

- **Hoá đơn** — theo ngày, chi tiết, thao tác thu tiền/ghi nợ/gán shipper/hoàn tác/xoá.
- **Thanh toán** — chi tiết thanh toán theo ngày, vuốt trái để xoá 1 dòng.
- **Công nợ** — danh sách hoá đơn còn nợ (bấm vào mở lại chi tiết Hoá đơn).
- **Chi tiêu** — chi tiêu hằng ngày + thêm chi tiêu mới (chọn nguyên liệu thật), vuốt trái để sửa ghi chú/xoá.
- **Thêm** →
  - **Công việc** — công việc nội bộ, tick hoàn thành + thêm việc mới.
  - **Báo cáo** — 7 trang theo tháng (Đơn Tại chỗ/Mua về/Ship/Mua hộ/App, Chi tiết tháng, Chi tiêu tháng).
  - **Thống kê** — doanh thu/thanh toán/chi tiêu/công nợ mới/trả nợ/đơn treo trong ngày + tổng công
    nợ luỹ kế, port từ `TraSuaApp.Desktop/Controls/ThongKeTabControl` (7 endpoint `/api/ThongKe/*`).
  - **Tài khoản** — tên đăng nhập + đăng xuất.
  - **Xem màn hình Desktop** — chọn 1 máy đang mở `TraSuaApp.Desktop` (poll qua hub `/hub/entity`),
    xem ảnh chụp cửa sổ chính cập nhật mỗi ~0.1s, giữ nguyên chiều dọc, 2 ngón zoom + 1 ngón kéo
    khung hình, nút X góc trên để thoát. Không phải VNC/video thật — chỉ đủ để canh máy đang chạy
    gì, không điều khiển được.

Còn thiếu (cố tình bỏ qua, làm sau): **Tạo hoá đơn** (CreatePlus) và tab **Đenn Signal**
(SignalR real-time + TTS, đã có plan duyệt sẵn từ trước — xem memory
`handoff_appmobileios_signal_tab`).

Đăng nhập chỉ có 1 ô mật khẩu — tài khoản luôn là `admin` (hardcode, ẩn khỏi UI), khớp
`AppMobileAndroid/LoginActivity.kt`.

## Build (không cần Mac)

CI (`.github/workflows/build-ios.yml`) chạy trên macOS runner của GitHub Actions, build ra
`AppMobileIOS-unsigned.ipa` — **CHƯA KÝ** (cố ý, để khỏi phải nhét Apple ID vào GitHub Secrets).

1. Push repo này lên GitHub.
2. Tab **Actions** → chạy workflow "Build unsigned iOS IPA" (hoặc tự chạy khi push lên `main`).
3. Xong, vào job → tải artifact `AppMobileIOS-unsigned-ipa`.

## Cài lên iPhone bằng Sideloadly (Windows, không cần Mac)

Cần cài **iTunes** (bản .exe cổ điển từ apple.com, không phải bản Microsoft Store) trước — Windows
cần driver "Apple Mobile Device Support" đi kèm để nhận diện iPhone qua USB, Sideloadly không tự
có driver này.

1. Cắm iPhone vào máy Windows qua cáp, mở khoá, bấm **Tin cậy** máy tính này nếu được hỏi.
2. Mở Sideloadly, kéo file `AppMobileIOS-unsigned.ipa` vào.
3. Chọn đúng thiết bị ở ô iDevice.
4. Nhập Apple ID cá nhân (dùng để ký) → bấm Start.
5. Trên iPhone: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → **Tin cậy** app vừa cài.
6. Lần đầu mở app: iOS đòi bật **Chế độ nhà phát triển** (Cài đặt → Quyền riêng tư & Bảo mật →
   cuối trang) → bật → khởi động lại máy → xác nhận bật → mở lại app.

Apple ID miễn phí: app tự gỡ sau 7 ngày, cắm lại máy chạy Sideloadly lần nữa để ký lại (dữ liệu
đăng nhập lưu `UserDefaults` sẽ mất khi cài đè, phải đăng nhập lại). Apple ID trả phí Developer
Program: ký được 1 năm.

## Cấu trúc code

- `Prefs.swift` — lưu token/refreshToken (`UserDefaults`, khớp `SharedPreferences` bên Android).
- `Models.swift` — DTO Codable, tên field khớp tuyệt đối JSON Backend trả về.
- `APIClient.swift` — gọi API, tự refresh token khi 401 rồi retry.
- `DateNav.swift` — `DayNavBar`/`MonthNavBar` dùng chung cho mọi tab theo ngày/tháng.
- `SearchBar.swift` — ô search + helper `matchesSearch`/`anyMatchesSearch` dùng chung mọi tab.
- `LoginView.swift`, `HoaDonListView.swift`, `HoaDonDetailView.swift`, `MainTabView.swift`.
- `ThanhToanListView.swift`, `CongNoListView.swift`, `CongViecListView.swift`,
  `ChiTieuListView.swift` (kèm `AddExpenseSheet` + sửa/xoá), `MonthListView.swift` (generic cho 7
  trang báo cáo + `BaoCaoMenuView`), `ThongKeView.swift`.
- `HoaDonFormatting.swift` — màu/format tiền/giờ/sort priority, khớp Android + `HoaDonSortService`
  bên Desktop.
- `SignalRClient.swift` — ngoài "EntityChanged" còn có `invoke()` (invocation kèm invocationId, đợi
  completion type 3) dùng cho `GetConnectedDesktops`/`RequestDesktopScreenshot`.
- `DesktopPickerView.swift`, `DesktopScreenView.swift` — tab "Xem màn hình Desktop": tự vào thẳng
  máy tên `DESKTOP-118TMVD` (`targetMachineName` hardcode, xác định bởi tên chứ không theo vị trí
  trong danh sách), không cần chọn tay; zoom/pan bằng gesture, giữ nguyên chiều dọc.

## Đổi icon

`Assets.xcassets/AppIcon.appiconset/` (nguồn gốc:
`TraSuaInternalSignalAndroid/app/src/main/res/drawable/denn_icon.png`, phóng lên nên hơi mờ ở cỡ
1024 — thay bằng file nét hơn nếu có).
