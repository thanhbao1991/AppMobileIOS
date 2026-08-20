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

        for kh in khachHangs {
            let phone = kh.phones.first?.soDienThoai.trimmingCharacters(in: .whitespaces) ?? ""
            guard !phone.isEmpty, !kh.ten.trimmingCharacters(in: .whitespaces).isEmpty else {
                result.skipped += 1
                continue
            }

            do {
                let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
                let matches = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

                if let existing = matches.first {
                    if existing.givenName != kh.ten {
                        let mutable = existing.mutableCopy() as! CNMutableContact
                        mutable.givenName = kh.ten
                        saveRequest.update(mutable)
                        hasPendingChanges = true
                        result.updated += 1
                    } else {
                        result.skipped += 1
                    }
                } else {
                    let newContact = CNMutableContact()
                    newContact.givenName = kh.ten
                    newContact.phoneNumbers = kh.phones.map {
                        CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0.soDienThoai))
                    }
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
