import AVFoundation
import CoreMedia
import CoreVideo
import UIKit
import libvpx

/// Giải mã VP9 phần mềm (libvpx, package `ronnyf/libvpx` branch `release/webrtc` — xem project.yml)
/// và đẩy vào `AVSampleBufferDisplayLayer` dưới dạng ảnh thô đã decode (KHÔNG giống `H264Decoder` cũ
/// — H264 đẩy thẳng NAL nén để layer tự decode phần cứng; VP9 không có hardware decode trên iOS nên
/// mình tự decode ra `CVPixelBuffer` I420 rồi mới đẩy vào layer làm khung hình thô).
///
/// CHƯA TEST TRÊN THIẾT BỊ THẬT (máy build .165 không có Xcode/Mac) — cần build qua CI + cài thử trên
/// iPhone thật, xem incident_screenagent_qsv_crash_vp9_fallback.md để biết vì sao đổi từ H264 sang VP9.
final class VP9Decoder {
    private let codecPtr: UnsafeMutablePointer<vpx_codec_ctx_t>
    private var initialized = false

    /// width/height thật của khung hình đã decode — dùng cho quy đổi toạ độ tap/pan/zoom, chỉ có
    /// giá trị SAU KHI đã decode được ít nhất 1 khung.
    private(set) var frameSize: CGSize?

    init() {
        codecPtr = UnsafeMutablePointer<vpx_codec_ctx_t>.allocate(capacity: 1)
        memset(codecPtr, 0, MemoryLayout<vpx_codec_ctx_t>.size)
    }

    deinit {
        if initialized { vpx_codec_destroy(codecPtr) }
        codecPtr.deallocate()
    }

    /// true nếu khung này làm frameSize thay đổi (khung đầu tiên, hoặc đổi độ phân giải).
    @discardableResult
    func feed(_ packet: Data, into layer: AVSampleBufferDisplayLayer) -> Bool {
        if !initialized {
            guard let iface = vpx_codec_vp9_dx() else { return false }
            let result = vpx_codec_dec_init_ver(
                codecPtr, iface, nil, 0, Int32(VPX_DECODER_ABI_VERSION))
            guard result == VPX_CODEC_OK else { return false }
            initialized = true
        }

        let decodeResult = packet.withUnsafeBytes { buf -> vpx_codec_err_t in
            guard let base = buf.bindMemory(to: UInt8.self).baseAddress else {
                return VPX_CODEC_ERROR
            }
            return vpx_codec_decode(codecPtr, base, UInt32(packet.count), nil, 0)
        }
        guard decodeResult == VPX_CODEC_OK else { return false }

        var iter: vpx_codec_iter_t?
        guard let imgPtr = vpx_codec_get_frame(codecPtr, &iter) else { return false }

        return enqueue(image: imgPtr, layer: layer)
    }

    private func enqueue(image imgPtr: UnsafeMutablePointer<vpx_image>, layer: AVSampleBufferDisplayLayer) -> Bool {
        let img = imgPtr.pointee
        let width = Int(img.d_w)
        let height = Int(img.d_h)
        guard width > 0, height > 0 else { return false }

        var formatChanged = false
        let newSize = CGSize(width: width, height: height)
        if frameSize != newSize {
            frameSize = newSize
            formatChanged = true
        }

        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_420YpCbCr8PlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBufferOut)
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else { return formatChanged }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        // vpx_image.planes/stride là C array cỡ 4 → Swift import thành tuple .0/.1/.2/.3. Plane 0=Y,
        // 1=U(Cb), 2=V(Cr) — đúng thứ tự CVPixelBuffer plane 420 Planar cũng dùng.
        copyPlane(src: img.planes.0, srcStride: Int(img.stride.0), dst: pixelBuffer, plane: 0, height: height)
        let chromaHeight = (height + 1) / 2
        copyPlane(src: img.planes.1, srcStride: Int(img.stride.1), dst: pixelBuffer, plane: 1, height: chromaHeight)
        copyPlane(src: img.planes.2, srcStride: Int(img.stride.2), dst: pixelBuffer, plane: 2, height: chromaHeight)

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return formatChanged }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)
        guard let sampleBuffer else { return formatChanged }

        // timing la .invalid (khong co PTS thuc) nen AVSampleBufferDisplayLayer se KHONG tu ve neu
        // khong danh dau DisplayImmediately - mac dinh no cho mot host-time hop le de dong bo, dan
        // toi layer nhan enqueue thanh cong (khong loi) nhung man hinh van den thui vinh vien.
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           let dict = CFArrayGetValueAtIndex(attachmentsArray, 0) {
            let attachments = unsafeBitCast(dict, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                attachments,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }

        if layer.status == .failed { layer.flush() }
        layer.enqueue(sampleBuffer)
        return formatChanged
    }

    private func copyPlane(
        src: UnsafeMutablePointer<UInt8>?, srcStride: Int, dst: CVPixelBuffer, plane: Int, height: Int
    ) {
        guard let src else { return }
        guard let dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else { return }
        let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
        let rowBytes = min(srcStride, dstStride)
        for row in 0..<height {
            memcpy(dstBase.advanced(by: row * dstStride), src.advanced(by: row * srcStride), rowBytes)
        }
    }
}
