import Foundation

/// Resumo do andamento do megafone, publicado em lote — pra telas que só mostram uma visão geral
/// (a row da conta na lista de contas, o resumo no topo da lista de publicados) observarem sem
/// recalcular a cada status de item individual.
///
/// `MegaphoneRunner.items` muda uma vez por produto megafonado (até 1500+ vezes numa rodada) — ler
/// direto dele nessas telas fazia o SwiftUI refazer o layout da lista de contas a cada produto, em
/// cada conta rodando ao mesmo tempo (ver `MegaphoneQueue`). Com várias lojas grandes megafonando
/// juntas, o efeito somado no main thread é jank/travamento na UI. Ver
/// `MegaphoneRunner.refreshProgressSnapshot(force:)`.
nonisolated struct MegaphoneProgressSnapshot: Equatable {
    var phase: MegaphonePhase = .idle
    var itemsCount = 0
    var processedCount = 0
    var totalSucceeded = 0
    var totalFailed = 0
    var round = 0
    /// Quantos produtos ainda vivos (nem apagados, nem inativados) pedem decisão de desconto — o
    /// selo "N pedem desconto" da lista de contas lê daqui, pra não precisar varrer `items`.
    var discountDecisionCount = 0

    var statusText: MegaphoneStatusText {
        MegaphoneStatusText(
            phase: phase,
            itemsCount: itemsCount,
            processedCount: processedCount,
            totalSucceeded: totalSucceeded,
            totalFailed: totalFailed,
            round: round
        )
    }
}
