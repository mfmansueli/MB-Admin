import Foundation

/// O que a Live Activity de uma rodada do megafone mostra — tela bloqueada e Dynamic Island. Os
/// textos já chegam prontos do app (ver `MegaphoneActivityContent+Snapshot.swift`): a extensão só
/// desenha, sem saber nada de `MegaphonePhase`/`MegaphoneProgressSnapshot`, que nem existem lá.
///
/// Compartilhado entre o app e a extensão `MB Admin LiveActivity` (pasta `Shared`) — é o
/// `ContentState` de `MegaphoneActivityAttributes`.
nonisolated struct MegaphoneActivityContent: Codable, Hashable, Sendable {
    /// O número grande: "12 de 340" megafonando; "esperando a vez", "buscando produtos"… antes de
    /// começar; "340 megafones" no fim.
    var title: String
    /// Cabe na Dynamic Island compacta: "12/340" (ou "…" antes de começar).
    var compactText: String
    /// "rodada 2 de 5" — `nil` numa rodada só.
    var roundText: String?
    /// De 0 a 1 — `nil` quando ainda não dá pra saber (esperando a vez, buscando a loja).
    var progress: Double?
    /// "2 com erro · 3 pedem desconto" — `nil` sem nada a dizer.
    var detailText: String?
    var isPaused: Bool
    /// A rodada acabou (concluída, interrompida ou com erro) — some o pausar/parar.
    var isFinished: Bool
}
