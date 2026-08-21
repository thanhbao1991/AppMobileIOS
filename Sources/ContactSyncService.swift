import Contacts
import Foundation

/// Đồng bộ tên KhachHang vào Danh bạ iPhone, để Caller ID hiện tên khách khi gọi đến — trigger
/// thủ công từ Menu (không chạy nền), theo yêu cầu user. Chỉ so khớp/ghi field
/// givenName + phoneNumbers + 2 urlAddress riêng (IdKhachHang, FacebookThreadId), không đụng
/// family name hay field khác nếu contact đã tồn tại, để không ghi đè dữ liệu cá nhân nhân viên
/// tự thêm vào danh bạ máy.
///
/// IdKhachHang + FacebookThreadId lưu vào urlAddresses (label riêng) thay vì note — field note
/// của Contacts cần entitlement riêng do Apple duyệt, urlAddresses thì không. Entry KhachHangId lưu
/// dạng link "trasuaapp://khachhang/{id}" bấm được thẳng từ app Danh bạ/Recents — DeepLinkRouter mở
/// app vào form tạo đơn Ship, prefill đúng khách đó (xem DeepLinkRouter.swift).
///
/// Khách không có SĐT (hoặc SĐT không hợp lệ) vẫn được sync — contact tạo ra chỉ có
/// givenName + urlAddresses, không có phoneNumbers. Match contact đã tồn tại theo SĐT thì được
/// (predicateForContacts nhanh), nhưng khách không SĐT thì không có gì để predicate theo, nên
/// phải match theo chính khachHangId đã nhúng sẵn trong urlAddresses — enumerate hết danh bạ máy
/// 1 lần (chỉ khi thật sự có khách không SĐT cần xử lý) để dựng dictionary id->contact.
enum ContactSyncService {
    static let khachHangIdLabel = "Tạo đơn ĐENN"
    static let threadIdLabel = "TraSuaApp FacebookThreadId"
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
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
        ]

        var result = SyncResult()

        // API trả về khachHangs đã sắp theo LastOrderAt ?? LastModified giảm dần (mới nhất trước) —
        // khi 2 khách trùng cùng 1 effectivePhone (số bị thu hồi/tái cấp cho người khác, hoặc quy
        // ước hậu tố chữ), giữ người xuất hiện TRƯỚC (hoạt động gần đây nhất), bỏ qua người còn lại
        // — không cần field ngày tháng riêng, tận dụng thứ tự sẵn có từ server.
        var claimedPhones = Set<String>()

        // Chỉ dựng khi gặp khách đầu tiên không có SĐT hợp lệ — enumerate hết danh bạ máy 1 lần,
        // tốn kém hơn predicate theo SĐT nên tránh làm nếu mọi khách đều có SĐT.
        var idIndex: [String: CNContact]?
        func resolveIdIndex() -> [String: CNContact] {
            if let idIndex { return idIndex }
            var map: [String: CNContact] = [:]
            let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
            try? store.enumerateContacts(with: fetchRequest) { contact, _ in
                for url in contact.urlAddresses where url.label == khachHangIdLabel {
                    if let id = (url.value as String).components(separatedBy: "/").last {
                        map[id] = contact
                    }
                }
            }
            idIndex = map
            return map
        }

        for kh in khachHangs {
            let ten = kh.ten.trimmingCharacters(in: .whitespaces)
            guard !ten.isEmpty else {
                result.skipped += 1
                continue
            }
            let phone = kh.phones.first.flatMap { effectivePhone($0.soDienThoai) }
            if let phone {
                guard !claimedPhones.contains(phone) else {
                    result.skipped += 1
                    continue
                }
                claimedPhones.insert(phone)
            }

            do {
                let existing: CNContact?
                if let phone {
                    let predicate = CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: phone))
                    existing = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch).first
                } else {
                    existing = resolveIdIndex()[kh.id]
                }

                if let existing {
                    let desiredUrls = mergedUrlAddresses(existing: existing.urlAddresses, kh: kh)
                    let nameChanged = existing.givenName != ten
                    // Tên khách trong DB luôn để hết vào givenName (không có family name riêng) —
                    // xoá trắng family name cũ nếu có, tránh hiện tên ghép sai kiểu "Ten FamilyNameCu"
                    // do nhân viên/hệ thống khác từng ghi vào đó.
                    let familyNameChanged = !existing.familyName.isEmpty
                    let urlsChanged = !urlAddressesEqual(existing.urlAddresses, desiredUrls)
                    if nameChanged || familyNameChanged || urlsChanged {
                        let mutable = existing.mutableCopy() as! CNMutableContact
                        if nameChanged { mutable.givenName = ten }
                        if familyNameChanged { mutable.familyName = "" }
                        if urlsChanged { mutable.urlAddresses = desiredUrls }
                        // Mỗi contact 1 CNSaveRequest riêng, execute ngay — nếu gộp chung 1 request
                        // cho hàng nghìn contact rồi execute 1 lần ở cuối, CHỈ 1 contact lỗi (vd contact
                        // từ nguồn CardDAV/Exchange không cho sửa familyName) là store.execute() ném lỗi
                        // và TOÀN BỘ batch bị rollback, không ai được lưu dù đa số hợp lệ.
                        let req = CNSaveRequest()
                        req.update(mutable)
                        do {
                            try store.execute(req)
                            result.updated += 1
                        } catch {
                            result.failed += 1
                        }
                    } else {
                        result.skipped += 1
                    }
                } else {
                    let newContact = CNMutableContact()
                    newContact.givenName = ten
                    if let phone {
                        newContact.phoneNumbers = [
                            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))
                        ]
                    }
                    newContact.urlAddresses = mergedUrlAddresses(existing: [], kh: kh)
                    let req = CNSaveRequest()
                    req.add(newContact, toContainerWithIdentifier: nil)
                    do {
                        try store.execute(req)
                        result.created += 1
                    } catch {
                        result.failed += 1
                    }
                }
            } catch {
                result.failed += 1
            }
        }

        return result
    }

    /// Giữ nguyên mọi urlAddress khác (nhân viên tự thêm), chỉ thay 2 entry gắn label
    /// khachHangIdLabel/threadIdLabel bằng giá trị mới nhất từ server. Bỏ entry threadId nếu
    /// khách chưa có FacebookThreadId.
    private static func mergedUrlAddresses(
        existing: [CNLabeledValue<NSString>], kh: KhachHangDto
    ) -> [CNLabeledValue<NSString>] {
        var result = existing.filter { $0.label != khachHangIdLabel && $0.label != threadIdLabel }
        result.append(CNLabeledValue(label: khachHangIdLabel, value: "trasuaapp://khachhang/\(kh.id)" as NSString))
        if let threadId = kh.facebookThreadId, !threadId.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(CNLabeledValue(label: threadIdLabel, value: threadId as NSString))
        }
        return result
    }

    private static func urlAddressesEqual(
        _ a: [CNLabeledValue<NSString>], _ b: [CNLabeledValue<NSString>]
    ) -> Bool {
        let toSet: ([CNLabeledValue<NSString>]) -> Set<String> = { list in
            Set(list.map { "\($0.label ?? "")=\($0.value)" })
        }
        return toSet(a) == toSet(b)
    }
}
