import Foundation

/// Parser tối giản cho message `EncodedVideoFrame` (protobuf THẬT của RustDesk/hbb_common,
/// `message.proto`: `bytes data = 1; bool key = 2; int64 pts = 3;`) — không dùng SwiftProtobuf (tránh
/// thêm SPM dependency, đúng tinh thần dự án hiện tại chỉ dùng thư viện chuẩn). Wire format protobuf
/// đơn giản đủ để tự đọc tay: mỗi field = varint tag (fieldNumber<<3 | wireType) rồi tới giá trị
/// (wireType 0 = varint, wireType 2 = length-delimited). Chỉ cần đọc field 1 (data) và field 2 (key),
/// bỏ qua field 3 (pts, không dùng ở iOS) và mọi field lạ khác (forward-compat).
enum EncodedVideoFrameProto {
    struct Frame {
        let data: Data
        let key: Bool
    }

    static func decode(_ bytes: Data) -> Frame? {
        let b = [UInt8](bytes)
        var i = 0
        var data = Data()
        var key = false

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]
                i += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }

        while i < b.count {
            guard let tag = readVarint() else { return nil }
            let fieldNumber = tag >> 3
            let wireType = tag & 0x7
            switch wireType {
            case 0: // varint
                guard let v = readVarint() else { return nil }
                if fieldNumber == 2 { key = v != 0 }
            case 2: // length-delimited
                guard let len = readVarint() else { return nil }
                let l = Int(len)
                guard l >= 0, i + l <= b.count else { return nil }
                if fieldNumber == 1 { data = Data(b[i..<(i + l)]) }
                i += l
            default:
                // wireType không xử lý (fixed32/fixed64...) — message này không dùng, coi như lỗi.
                return nil
            }
        }
        return Frame(data: data, key: key)
    }
}
