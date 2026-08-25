import SwiftUI
import UIKit

/// View vô hình bắt bàn phím thô (không dùng UITextField vì cần override cả phím mũi tên qua
/// `keyCommands`, UITextField sẽ nuốt trước khi tới được đây). `insertText` nhận ký tự thường (kể cả
/// chuỗi dài do gõ nhanh/gợi ý) VÀ "\n" khi bấm Return — tách riêng ra thành phím đặc biệt.
final class KeyCaptureUIView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onSpecialKey: ((String) -> Void)?

    var hasText: Bool { false }

    func insertText(_ text: String) {
        if text == "\n" {
            onSpecialKey?("Enter")
        } else {
            onInsertText?(text)
        }
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handleLeft)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleRight)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleDown)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscape)),
        ]
    }

    @objc private func handleLeft() { onSpecialKey?("ArrowLeft") }
    @objc private func handleRight() { onSpecialKey?("ArrowRight") }
    @objc private func handleUp() { onSpecialKey?("ArrowUp") }
    @objc private func handleDown() { onSpecialKey?("ArrowDown") }
    @objc private func handleEscape() { onSpecialKey?("Escape") }
}

struct KeyCaptureView: UIViewRepresentable {
    @Binding var isActive: Bool
    let onText: (String) -> Void
    let onSpecial: (String) -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onInsertText = onText
        view.onDeleteBackward = { onSpecial("Backspace") }
        view.onSpecialKey = onSpecial
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        if isActive && !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isActive && uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }
}

/// TOÀN BỘ cử chỉ điều khiển (tap=click, 1 ngón kéo=pan khung nhìn, 2 ngón kéo=cuộn, pinch=zoom) xử
/// lý bằng touchesBegan/Moved/Ended THÔ trong 1 view duy nhất — KHÔNG compose nhiều gesture
/// recognizer độc lập (SwiftUI DragGesture/MagnificationGesture + UIPanGestureRecognizer riêng),
/// vì các recognizer độc lập nằm trên các view khác nhau KHÔNG tự loại trừ nhau — thực tế đã gây bug
/// vừa gửi lệnh chuột vừa cuộn khi chạm 2 ngón. Cùng kiến trúc RustDesk dùng (1 vùng nhận raw touch,
/// tự phân giải ngữ nghĩa gesture, xem `flutter/lib/mobile/pages/remote_page.dart` —
/// `RawTouchGestureDetectorRegion`) — chỉ tham khảo Ý TƯỞNG kiến trúc, code bên dưới tự viết lại.
final class RemoteControlSurfaceView: UIView {
    var onTap: ((CGPoint) -> Void)?
    var onLongPress: ((CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private enum Mode { case idle, single, multi }
    private var mode: Mode = .idle
    private var trackedTouches: [UITouch] = []

    // 1 ngón: pan khi di chuyển thật sự vượt ngưỡng (đủ lớn để không nhầm rung tay khi chạm nhẹ
    // thành kéo). Quyết định tap/long-press CHỈ khi thả tay (KHÔNG dùng Timer — không đáng tin cậy
    // giữa lúc đang track touch, timer có thể không kịp fire đúng lúc): thả tay mà tổng di chuyển
    // vẫn nhỏ hơn ngưỡng → giữ đủ lâu (elapsed ≥ longPressDelay) = long-press = chuột phải, ngược
    // lại = tap thường = chuột trái.
    private let moveThreshold: CGFloat = 12
    private let longPressDelay: TimeInterval = 0.5
    private var singleStart: CGPoint = .zero
    private var singleLast: CGPoint = .zero
    private var singleDownAt: Date = .distantPast
    private var singleMoved = false

    // Đã từng có ≥2 ngón trong lượt chạm hiện tại — chặn hẳn tap/pan cho ngón còn sót lại lúc nhấc
    // bớt 1 ngón, tới khi TẤT CẢ ngón rời khỏi màn hình (count về 0) mới reset cho lượt chạm kế tiếp.
    private var hadMultiTouch = false

    private var multiLastMidY: CGFloat = 0
    private var multiLastDistance: CGFloat = 0

    // 2 ngón thật (rung tay) luôn lẫn 1 chút cả 2 loại chuyển động — CHỈ áp dụng MỘT trong 2 hành vi
    // (cuộn hoặc zoom) cho trọn lượt chạm hiện tại, quyết định bằng tổng biên độ nào vượt trội hẳn,
    // tránh vừa cuộn vừa zoom giật cục ngoài ý muốn.
    private enum MultiIntent { case undecided, scroll, zoom }
    private var multiIntent: MultiIntent = .undecided
    private var multiCumScroll: CGFloat = 0
    private var multiCumPinch: CGFloat = 0
    private let multiDecideThreshold: CGFloat = 8

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        resyncTrackedTouches(event)
        refreshMode()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch mode {
        case .single:
            guard let t = trackedTouches.first else { return }
            let loc = t.location(in: self)
            if !singleMoved, hypot(loc.x - singleStart.x, loc.y - singleStart.y) > moveThreshold {
                singleMoved = true
            }
            if singleMoved {
                onPan?(CGSize(width: loc.x - singleLast.x, height: loc.y - singleLast.y))
            }
            singleLast = loc
        case .multi:
            guard trackedTouches.count >= 2 else { return }
            let p0 = trackedTouches[0].location(in: self)
            let p1 = trackedTouches[1].location(in: self)
            let midY = (p0.y + p1.y) / 2
            let distance = max(1, hypot(p0.x - p1.x, p0.y - p1.y))
            let scrollDelta = midY - multiLastMidY
            let distanceDelta = distance - multiLastDistance
            let pinchFactor = multiLastDistance > 0 ? distance / multiLastDistance : 1
            multiLastMidY = midY
            multiLastDistance = distance

            switch multiIntent {
            case .scroll:
                onScroll?(CGPoint(x: (p0.x + p1.x) / 2, y: midY), scrollDelta)
            case .zoom:
                onPinch?(pinchFactor)
            case .undecided:
                multiCumScroll += abs(scrollDelta)
                multiCumPinch += abs(distanceDelta)
                if multiCumScroll > multiCumPinch * 2, multiCumScroll > multiDecideThreshold {
                    multiIntent = .scroll
                } else if multiCumPinch > multiCumScroll * 2, multiCumPinch > multiDecideThreshold {
                    multiIntent = .zoom
                }
            }
        case .idle:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if mode == .single, !singleMoved, !hadMultiTouch {
            if Date().timeIntervalSince(singleDownAt) >= longPressDelay {
                onLongPress?(singleStart)
            } else {
                onTap?(singleStart)
            }
        }
        resyncTrackedTouches(event)
        refreshMode()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        resyncTrackedTouches(event)
        refreshMode()
    }

    // Đồng bộ lại từ `event` (nguồn sự thật của hệ thống) thay vì tự cộng dồn/gỡ thủ công trên mảng
    // riêng — nếu 1 lần touchesEnded/Cancelled bị lỡ (vd đổi app iOS giữa lúc đang pinch 2 ngón),
    // mảng tự quản lý cũ sẽ giữ ngón "ma" mãi mãi, khiến `hadMultiTouch` kẹt true vĩnh viễn và MỌI
    // tap/long-press sau đó bị chặn câm lặng cho tới khi khởi động lại app (bug nghi ngờ gây ra "tap
    // không hoạt động" dù mọi thứ khác đều đúng — xem cách RustDesk né hẳn lớp bug này bằng cách
    // dùng GestureRecognizer chuẩn của framework thay vì tự track touch thủ công).
    private func resyncTrackedTouches(_ event: UIEvent?) {
        guard let all = event?.touches(for: self) else { trackedTouches = []; return }
        trackedTouches = all.filter { $0.phase != .ended && $0.phase != .cancelled }
    }

    private func refreshMode() {
        switch trackedTouches.count {
        case 0:
            mode = .idle
            hadMultiTouch = false
        case 1:
            mode = .single
            if hadMultiTouch {
                // Ngón còn sót lại sau khi vừa nhấc bớt từ 2→1 — không coi là bắt đầu gesture mới.
                singleMoved = true
            } else {
                let loc = trackedTouches[0].location(in: self)
                singleStart = loc
                singleLast = loc
                singleDownAt = Date()
                singleMoved = false
            }
        default:
            mode = .multi
            hadMultiTouch = true
            multiIntent = .undecided
            multiCumScroll = 0
            multiCumPinch = 0
            let p0 = trackedTouches[0].location(in: self)
            let p1 = trackedTouches[1].location(in: self)
            multiLastMidY = (p0.y + p1.y) / 2
            multiLastDistance = max(1, hypot(p0.x - p1.x, p0.y - p1.y))
        }
    }
}

struct RemoteControlSurface: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void
    let onPan: (CGSize) -> Void
    let onScroll: (CGPoint, CGFloat) -> Void
    let onPinch: (CGFloat) -> Void

    func makeUIView(context: Context) -> RemoteControlSurfaceView {
        let view = RemoteControlSurfaceView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: RemoteControlSurfaceView, context: Context) {
        uiView.onTap = onTap
        uiView.onLongPress = onLongPress
        uiView.onPan = onPan
        uiView.onScroll = onScroll
        uiView.onPinch = onPinch
    }
}
