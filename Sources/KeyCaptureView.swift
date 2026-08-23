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
    var onPan: ((CGSize) -> Void)?
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    var onPinch: ((CGFloat) -> Void)?

    private enum Mode { case idle, single, multi }
    private var mode: Mode = .idle
    private var trackedTouches: [UITouch] = []

    // 1 ngón: chỉ pan khi di chuyển thật sự (> ngưỡng), thả tay không di chuyển mới coi là tap=click.
    private var singleStart: CGPoint = .zero
    private var singleLast: CGPoint = .zero
    private var singleMoved = false

    // Đã từng có ≥2 ngón trong lượt chạm hiện tại — chặn hẳn tap/pan cho ngón còn sót lại lúc nhấc
    // bớt 1 ngón, tới khi TẤT CẢ ngón rời khỏi màn hình (count về 0) mới reset cho lượt chạm kế tiếp.
    private var hadMultiTouch = false

    private var multiLastMidY: CGFloat = 0
    private var multiLastDistance: CGFloat = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedTouches.append(contentsOf: touches)
        refreshMode()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch mode {
        case .single:
            guard let t = trackedTouches.first else { return }
            let loc = t.location(in: self)
            if hypot(loc.x - singleStart.x, loc.y - singleStart.y) > 6 { singleMoved = true }
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
            onScroll?(CGPoint(x: (p0.x + p1.x) / 2, y: midY), midY - multiLastMidY)
            if multiLastDistance > 0 { onPinch?(distance / multiLastDistance) }
            multiLastMidY = midY
            multiLastDistance = distance
        case .idle:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if mode == .single, !singleMoved, !hadMultiTouch { onTap?(singleStart) }
        trackedTouches.removeAll { touches.contains($0) }
        refreshMode()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        trackedTouches.removeAll { touches.contains($0) }
        refreshMode()
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
                singleMoved = false
            }
        default:
            mode = .multi
            hadMultiTouch = true
            let p0 = trackedTouches[0].location(in: self)
            let p1 = trackedTouches[1].location(in: self)
            multiLastMidY = (p0.y + p1.y) / 2
            multiLastDistance = max(1, hypot(p0.x - p1.x, p0.y - p1.y))
        }
    }
}

struct RemoteControlSurface: UIViewRepresentable {
    let onTap: (CGPoint) -> Void
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
        uiView.onPan = onPan
        uiView.onScroll = onScroll
        uiView.onPinch = onPinch
    }
}
