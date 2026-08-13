# AppMobileIOS

Bọc native WKWebView cho TraSuaApp.Mobile (`https://mobile.denncoffee.uk/`) — dùng thay Safari
trên iPhone: có icon riêng, mở lên không có thanh địa chỉ/tab. Không cần push/nền nên không cần
tài khoản Apple Developer Program ($99/năm).

## Build (không cần Mac)

CI (`.github/workflows/build-ios.yml`) chạy trên macOS runner của GitHub Actions, build ra
`AppMobileIOS-unsigned.ipa` — **CHƯA KÝ** (cố ý, để khỏi phải nhét Apple ID vào GitHub Secrets).

1. Push repo này lên GitHub.
2. Tab **Actions** → chạy workflow "Build unsigned iOS IPA" (hoặc tự chạy khi push lên `main`).
3. Xong, vào job → tải artifact `AppMobileIOS-unsigned-ipa`.

## Cài lên iPhone bằng Sideloadly (Windows, không cần Mac)

1. Tải Sideloadly: https://sideloadly.io
2. Cắm iPhone vào máy Windows qua cáp, mở Sideloadly.
3. Kéo file `AppMobileIOS-unsigned.ipa` vào Sideloadly.
4. Nhập Apple ID cá nhân (dùng để ký) → bấm Start.
5. Trên iPhone: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → **Tin cậy** app vừa cài.

Apple ID miễn phí: app tự gỡ sau 7 ngày, cắm lại máy chạy Sideloadly lần nữa để ký lại (không mất
dữ liệu app, WKWebView vẫn load lại được ngay). Apple ID trả phí Developer Program: ký được 1 năm.

## Đổi URL / icon

- URL web app: `Sources/ContentView.swift` (`mobileUrl`).
- Icon: `Assets.xcassets/AppIcon.appiconset/` (nguồn gốc:
  `TraSuaInternalSignalAndroid/app/src/main/res/drawable/denn_icon.png`, phóng lên nên hơi mờ ở
  cỡ 1024 — thay bằng file nét hơn nếu có).
