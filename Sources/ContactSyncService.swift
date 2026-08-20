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

    /// Chuẩn hoá SĐT để chỉ sync số hợp lệ, bỏ hậu tố chữ (vd "0944806299A" -> "0944806299") —
    /// hậu tố chữ là quy ước cũ đánh dấu 2 khách dùng chung 1 số thật (nhà/cơ quan chung đường
    /// dây), không phải số sai. Trả nil nếu không phải số điện thoại hợp lệ (số giữ chỗ
    /// "0000000xxx", quá ngắn/dài, không phải toàn chữ số...) — những trường hợp này bị loại
    /// hẳn khỏi sync để không tạo contact rác.
    private static func effectivePhone(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 10, trimmed.allSatisfy(\.isNumber), trimmed.hasPrefix("0"), !trimmed.hasPrefix("000000") {
            return trimmed
        }
        if trimmed.count == 11, trimmed.hasPrefix("0"), trimmed.last?.isLetter == true {
            let digits = String(trimmed.dropLast())
            if digits.allSatisfy(\.isNumber), !digits.hasPrefix("000000") {
                return digits
            }
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
