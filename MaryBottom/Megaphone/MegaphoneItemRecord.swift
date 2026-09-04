import Foundation
import SwiftData

/// Registro SwiftData de um produto carregado pelo megafone — mesmo raciocínio de
/// `InactiveProductRecord`: o `MegaphoneItem` inteiro codificado em `payload`, `sortIndex`
/// preservando a ordem original da vitrine.
@Model
final class MegaphoneItemRecord {
    var accountID: EnjoeiAccountID
    var sortIndex: Int
    var payload: Data

    init(accountID: EnjoeiAccountID, sortIndex: Int, payload: Data) {
        self.accountID = accountID
        self.sortIndex = sortIndex
        self.payload = payload
    }
}
