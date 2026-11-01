import Foundation

/// O que persiste em disco sobre uma conta entre uma abertura do app e outra — sem `runner`,
/// `client` ou `webView`, que são só de runtime.
nonisolated struct AccountRecord: Equatable, Sendable, Codable {
    let id: EnjoeiAccountID
    var user: EnjoeiUser
    var lastRoundSummary: MegaphoneRoundSummary?
    /// Último toque em "recarregar produtos" (`AccountSession.reloadAllProducts`) — `nil` se nunca
    /// tocou. Opcional também pra continuar lendo o que foi salvo antes deste campo existir.
    var lastCatalogRefresh: Date?
}
