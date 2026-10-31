import Foundation

/// Os dois ritmos da fila de ações, cada um com o próprio intervalo escolhido no menu da tela da
/// fila: postar, repostar e apagar (criar ou sumir com um anúncio, a partir de 30s), e ativar e
/// inativar (só trocar o estado de um anúncio que já existe, que aguenta ir mais rápido, a partir
/// de 15s). A espera antes de cada ação usa o intervalo do grupo dela (`PostQueue.waitInterval`).
nonisolated enum PostQueueIntervalGroup: CaseIterable, Hashable, Sendable {
    case posting
    case statusChange

    init(kind: PostQueueItem.Kind) {
        switch kind {
        case .post, .delete: self = .posting
        case .inactivate, .activate: self = .statusChange
        }
    }

    /// Opções do menu, da mais rápida pra mais lenta — 15s só pra ativar e inativar.
    var presets: [TimeInterval] {
        switch self {
        case .posting: [30, 60, 120, 180, 240, 300]
        case .statusChange: [15, 30, 60, 120, 180, 240, 300]
        }
    }

    /// Antes de o usuário escolher alguma coisa no menu.
    var defaultInterval: TimeInterval {
        switch self {
        case .posting: 30
        case .statusChange: 15
        }
    }

    /// Título da seção do menu de intervalo e nome do grupo no cartão da fila.
    var title: String {
        switch self {
        case .posting: "postar, repostar e apagar"
        case .statusChange: "ativar e inativar"
        }
    }

    /// Onde a escolha fica guardada. `postQueue.interval` é a chave de antes de existirem dois
    /// grupos (um intervalo só pra tudo) — mantida pra postar, pra quem já tinha escolhido um não
    /// perder a escolha.
    var defaultsKey: String {
        switch self {
        case .posting: "postQueue.interval"
        case .statusChange: "postQueue.interval.statusChange"
        }
    }
}
