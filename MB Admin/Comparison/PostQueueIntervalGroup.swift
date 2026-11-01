import Foundation

/// Os dois ritmos da fila de ações, cada um com o próprio intervalo escolhido no menu da tela da
/// fila: postar e repostar (criar um anúncio novo, a partir de 30s), e ativar, inativar e apagar
/// (mexer num anúncio que já existe, que aguenta ir bem mais rápido — a partir de 5s, com 10s de
/// padrão). A espera antes de cada ação usa o intervalo do grupo dela (`PostQueue.waitInterval`).
nonisolated enum PostQueueIntervalGroup: CaseIterable, Hashable, Sendable {
    case posting
    case listingChange

    init(kind: PostQueueItem.Kind) {
        switch kind {
        case .post: self = .posting
        case .delete, .inactivate, .activate: self = .listingChange
        }
    }

    /// Opções do menu, da mais rápida pra mais lenta — 5s, 10s e 15s só pra ativar, inativar e
    /// apagar.
    var presets: [TimeInterval] {
        switch self {
        case .posting: [30, 60, 120, 180, 240, 300]
        case .listingChange: [5, 10, 15, 30, 60, 120, 180, 240, 300]
        }
    }

    /// Antes de o usuário escolher alguma coisa no menu.
    var defaultInterval: TimeInterval {
        switch self {
        case .posting: 30
        case .listingChange: 10
        }
    }

    /// Título da seção do menu de intervalo e nome do grupo no cartão da fila.
    var title: String {
        switch self {
        case .posting: "postar e repostar"
        case .listingChange: "ativar, inativar e apagar"
        }
    }

    /// Onde a escolha fica guardada. `postQueue.interval` é a chave de antes de existirem dois
    /// grupos (um intervalo só pra tudo) — mantida pra postar, pra quem já tinha escolhido um não
    /// perder a escolha. A do outro grupo é nova de propósito: `postQueue.interval.statusChange`
    /// era a de quando ele era só ativar e inativar, com 15s de padrão — herdar aquela escolha
    /// deixaria apagar (que antes andava no ritmo de postar) e o padrão novo de 10s sem efeito.
    var defaultsKey: String {
        switch self {
        case .posting: "postQueue.interval"
        case .listingChange: "postQueue.interval.listingChange"
        }
    }
}
