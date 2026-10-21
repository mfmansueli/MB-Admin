import Foundation

/// Ponte entre os botões da Live Activity (`ToggleMegaphonePauseIntent`/`StopMegaphoneIntent`) e as
/// contas do app. O sistema roda esses intents no processo do app, mas eles não enxergam
/// `AccountsStore` — quem tem as contas registra aqui o que fazer (ver `AccountsStore.init`).
///
/// Compilado também na extensão (pasta `Shared`), onde ninguém registra nada: lá os intents só
/// existem pra montar os botões.
@MainActor
final class MegaphoneLiveActivityCommands {
    enum Command: Sendable {
        case togglePause
        case stop
    }

    static let shared = MegaphoneLiveActivityCommands()

    var handler: ((Command, UUID) -> Void)?

    func send(_ command: Command, accountID: UUID) {
        handler?(command, accountID)
    }
}
