# AppMobileIOS

App **native thật** (SwiftUI, không phải WebView bọc web) cho ĐENN — gọi thẳng
`TraSuaApp.Backend` API, port từ `AppMobileAndroid`. Hiện chỉ tab **Hoá đơn** (theo ngày, chi
tiết, thao tác thu tiền/ghi nợ/gán shipper/hoàn tác/xoá) có nội dung đầy đủ — các tab khác
(Thanh toán/Công nợ/Chi tiêu) là vỏ "Sắp có", làm sau.

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
- `Models.swift` — DTO Codable, port 1:1 `AppMobileAndroid/Dtos.kt`.
- `APIClient.swift` — gọi API, tự refresh token khi 401, port `AppMobileAndroid/ApiClient.kt`.
- `LoginView.swift`, `HoaDonListView.swift`, `HoaDonDetailView.swift`, `MainTabView.swift`.
- `HoaDonFormatting.swift` — màu/format tiền/giờ/sort priority, khớp Android + `HoaDonSortService`
  bên Desktop.

## Đổi icon

`Assets.xcassets/AppIcon.appiconset/` (nguồn gốc:
`TraSuaInternalSignalAndroid/app/src/main/res/drawable/denn_icon.png`, phóng lên nên hơi mờ ở cỡ
1024 — thay bằng file nét hơn nếu có).
