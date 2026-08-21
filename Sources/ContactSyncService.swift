import Contacts
import Foundation

/// Đồng bộ tên KhachHang vào Danh bạ iPhone theo SĐT, để Caller ID hiện tên khách khi gọi đến —
/// trigger thủ công từ Menu (không chạy nền), theo yêu cầu user. Chỉ so khớp/ghi field
/// givenName + phoneNumbers, không đụng family name hay field khác nếu contact đã tồn tại, để
/// không ghi đè dữ liệu cá nhân nhân viên tự thêm vào danh bạ máy.
enum ContactSyncService {
    struct SyncResult {
        var created = 0
        var updated = 0
        var skipped = 0
        var failed = 0

        var summary: String {
            "Tạo mới \(created), cập nhật \(updated), bỏ qua \(skipped)" + (failed > 0 ? ", lỗi \(failed)" : "")
        }
    }

    enum SyncError: Error {
        case accessDenied
    }

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { cont in
            CNContactStore().requestAccess(for: .contacts) { granted, _ in
                cont.resume(returning: granted)
            }
        }
    }

    /// SĐT di động VN thật: đúng 10 số, số đầu = 0, số thứ 2 khác 0 (mọi đầu số 03/05/07/08/09
    /// đều có số thứ 2 khác 0 — quy tắc này tự động loại số giữ chỗ "0000000xxx" mà không cần
    /// liệt kê riêng), các số còn lại tự do 0-9.
    private static func isValidVNPhone(_ s: String) -> Bool {
        guard s.count == 10, s.allSatisfy(\.isNumber) else { return false }
        let chars = Array(s)
        return chars[0] == "0" && chars[1] != "0"
    }

    /// Chuẩn hoá SĐT để chỉ sync số hợp lệ, bỏ hậu tố chữ (vd "0944806299A" -> "0944806299") —
    /// hậu tố chữ là quy ước cũ đánh dấu 2 khách dùng chung 1 số thật (nhà/cơ quan chung đường
    /// dây), không phải số sai. Trả nil nếu không phải số điện thoại hợp lệ — bị loại hẳn khỏi
    /// sync để không tạo contact rác.
    private static func effectivePhone(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if isValidVNPhone(trimmed) { return trimmed }
        if trimmed.count == 11, trimmed.last?.isLetter == true {
            let digits = String(trimmed.dropLast())
            if isValidVNPhone(digits) { return digits }
        }
        return nil
    }

    static func sync(khachHangs: [KhachHangDto]) async throws -> SyncResult {
        guard await requestAccess() else { throw SyncError.accessDenied }

        let store = CNContactStore()
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
        ]

        var result = SyncResult()
        let saveRequest = CNSaveRequest()
        var hasPendingChanges = false

        // API trả về khachHangs đã sắp theo LastOrderAt ?? LastModified giảm dần (mới nhất trước) —
        // khi 2 khách trùng cùng 1 effectivePhone (số bị thu hồi/tái cấp cho người khác, hoặc quy
        // ước hậu tố chữ), giữ người xuất hiện TRƯỚC (hoạt động gần đây nhất), bỏ qua người còn lại
        // — không cần field ngày tháng riêng, tận dụng thứ tự sẵn có từ server.
        var claimedPhones = Set<String>()

        for kh in khachHangs {
            let ten = kh.ten.trimmingCharacters(in: .whitespaces)
            guard let phone = kh.phones.first.flatMap({ effectivePhone($0.soDienThoai) }), !ten.isEmpty else {
                result.skipped += 1
                continue
            }
            guard !claimedPhones.contains(phone) else {
                result.skipped += 1
                continue
            }
            claimedPhones.insert(phone)

            do {
                let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
                let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

                if let existing = matches.first {
                    if existing.givenName != ten {
                        let mutable = existing.mutableCopy() as! CNMutableContact
                        mutable.givenName = ten
                        saveRequest.update(mutable)
                        hasPendingChanges = true
                        result.updated += 1
                    } else {
                        result.skipped += 1
                    }
                } else {
                    let newContact = CNMutableContact()
                    newContact.givenName = ten
                    newContact.phoneNumbers = [
                        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
                    ]
                    saveRequest.add(newContact, toContainerWithIdentifier: nil)
                    hasPendingChanges = true
                    result.created += 1
                }
            } catch {
                result.failed += 1
            }
        }

        if hasPendingChanges {
            try store.execute(saveRequest)
        }
        return result
    }
}
