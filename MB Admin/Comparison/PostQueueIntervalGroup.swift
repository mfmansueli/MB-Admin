import Foundation

/// Os dois ritmos da fila de ações, cada um com o próprio intervalo escolhido no menu da tela da
/// fila: postar, repostar e apagar (criar ou tirar um anúncio da loja, a partir de 30s) e inativar
/// (a partir de 15s). A espera antes de cada ação usa o intervalo do grupo dela
/// (`PostQueue.waitInterval`).
nonisolated enum PostQueueIntervalGroup: CaseIterable, Hashable, Sendable {
    case posting
    case inactivating

    /// Ativar não entra mais na fila (saiu da aba de inativos); um item de ativar que ainda estava
    /// lá de antes anda no ritmo de inativar, que é a mesma mudança no sentido contrário.
    init(kind: PostQueueItem.Kind) {
        switch kind {
        case .post, .delete: self = .posting
        case .inactivate, .activate: self = .inactivating
        }
    }

    /// Opções do menu, da mais rápida pra mais lenta — a primeira é o mínimo do grupo.
    var presets: [TimeInterval] {
        switch self {
        case .posting: [30, 60, 120, 180, 240, 300]
        case .inactivating: [15, 30, 60, 120, 180, 240, 300]
        }
    }

    /// O mais rápido que o grupo anda: uma escolha guardada abaixo disso (de quando apagar e
    /// inativar desciam até 5s) sobe pra cá ao abrir o app (`PostQueue.init`).
    var minimumInterval: TimeInterval { presets[0] }

    /// Antes de o usuário escolher alguma coisa no menu — o próprio mínimo.
    var defaultInterval: TimeInterval { minimumInterval }

    /// Título da seção do menu de intervalo e nome do grupo no cartão da fila.
    var title: String {
        switch self {
        case .posting: "postar, repostar e apagar"
        case .inactivating: "inativar"
        }
    }

    /// Onde a escolha fica guardada. `postQueue.interval` é a chave de antes de existirem dois
    /// grupos — mantida pra postar, pra quem já tinha escolhido um não perder a escolha (apagar
    /// passa a seguir ela). A de inativar é nova de propósito: `postQueue.interval.listingChange`
    /// era a de ativar, inativar e apagar juntos, descendo até 5s — herdar aquela escolha
    /// deixaria o padrão novo de 15s sem efeito.
    var defaultsKey: String {
        switch self {
        case .posting: "postQueue.interval"
        case .inactivating: "postQueue.interval.inactivate"
        }
    }
}
