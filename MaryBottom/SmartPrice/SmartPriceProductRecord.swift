import Foundation
import SwiftData

/// Registro SwiftData de um produto sem preço esperto — mesmo raciocínio de `InactiveProductRecord`:
/// o `SmartPriceProduct` inteiro codificado em `payload`, `sortIndex` preservando a ordem original
/// da página.
@Model
final class SmartPriceProductRecord {
    var accountID: EnjoeiAccountID
    var sortIndex: Int
    var payload: Data

    init(accountID: EnjoeiAccountID, sortIndex: Int, payload: Data) {
        self.accountID = accountID
        self.sortIndex = sortIndex
        self.payload = payload
    }
}
