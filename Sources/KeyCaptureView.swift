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

    // 1 ngón: chỉ pan khi di chuyển thật sự (> ngưỡng), thả tay không di chuyển mới coi là tap=click.
    // Giữ yên > longPressDelay không di chuyển = long-press = click chuột phải (huỷ tap thường).
    private var singleStart: CGPoint = .zero
    private var singleLast: CGPoint = .zero
    private var singleMoved = false
    private var longPressTimer: Timer?
    private var longPressFired = false
    private let longPressDelay: TimeInterval = 0.5

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
        trackedTouches.append(contentsOf: touches)
        refreshMode()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        switch mode {
        case .single:
            guard let t = trackedTouches.first else { return }
            let loc = t.location(in: self)
            if hypot(loc.x - singleStart.x, loc.y - singleStart.y) > 6 {
                singleMoved = true
                cancelLongPressTimer()
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
        if mode == .single, !singleMoved, !hadMultiTouch, !longPressFired { onTap?(singleStart) }
        cancelLongPressTimer()
        trackedTouches.removeAll { touches.contains($0) }
        refreshMode()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelLongPressTimer()
        trackedTouches.removeAll { touches.contains($0) }
        refreshMode()
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func refreshMode() {
        switch trackedTouches.count {
        case 0:
            mode = .idle
            hadMultiTouch = false
            longPressFired = false
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
                longPressFired = false
                cancelLongPressTimer()
                longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDelay, repeats: false) { [weak self] _ in
                    guard let self, self.mode == .single, !self.singleMoved, !self.hadMultiTouch else { return }
                    self.longPressFired = true
                    self.onLongPress?(self.singleStart)
                }
            }
        default:
            mode = .multi
            hadMultiTouch = true
            cancelLongPressTimer()
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
