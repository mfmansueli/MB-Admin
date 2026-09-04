import Foundation
import SwiftData

/// Registro SwiftData de um produto inativo — guarda o `InactiveProduct` inteiro já codificado em
/// `payload` (mesmo raciocínio de `PostHistoryRecord`, pra não duplicar o esquema do modelo).
/// `sortIndex` preserva a ordem original da página (a lista não é reordenada ao salvar/reler, só
/// dividida em registros individuais).
@Model
final class InactiveProductRecord {
    var accountID: EnjoeiAccountID
    var sortIndex: Int
    var payload: Data

    init(accountID: EnjoeiAccountID, sortIndex: Int, payload: Data) {
        self.accountID = accountID
        self.sortIndex = sortIndex
        self.payload = payload
    }
}
