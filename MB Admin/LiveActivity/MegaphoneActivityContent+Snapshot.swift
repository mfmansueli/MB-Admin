import Foundation

/// Monta o que a Live Activity mostra a partir do resumo da rodada — do lado do app, porque a
/// extensão não conhece `MegaphoneProgressSnapshot`.
extension MegaphoneActivityContent {
    init(snapshot: MegaphoneProgressSnapshot) {
        let status = snapshot.statusText
        // Só o que pede atenção: zero erros e zero descontos não viram texto.
        let attention = [
            snapshot.totalFailed > 0 ? "\(snapshot.totalFailed.formatted()) com erro" : nil,
            snapshot.discountDecisionCount > 0 ? "\(snapshot.discountDecisionCount.formatted()) pedem desconto" : nil
        ].compactMap { $0 }
        let attentionText = attention.isEmpty ? nil : attention.joined(separator: " · ")

        roundText = nil
        progress = nil
        detailText = attentionText
        isPaused = false
        isFinished = false

        switch snapshot.phase {
        case .megaphoning, .paused:
            // O laço publica "processados" — o da vez é o seguinte, sem passar do total no fim da
            // rodada.
            let current = min(snapshot.processedCount + 1, snapshot.itemsCount)
            title = "\(current.formatted()) de \(snapshot.itemsCount.formatted())"
            compactText = "\(current)/\(snapshot.itemsCount)"
            roundText = status.roundLabel
            progress = status.progress
            if case .paused = snapshot.phase { isPaused = true }
        case .waitingInQueue:
            title = "esperando a vez"
            compactText = "…"
        case .loadingProducts:
            title = "buscando produtos"
            compactText = "…"
            progress = status.progress
        case .checkingExposure:
            title = "conferindo descontos"
            compactText = "…"
            progress = status.progress
        case .finished:
            title = "\(snapshot.totalSucceeded.formatted()) megafones"
            compactText = "fim"
            progress = 1
            isFinished = true
        case .cancelled:
            title = "interrompido"
            compactText = "parou"
            detailText = (["\(snapshot.totalSucceeded.formatted()) megafones"] + attention).joined(separator: " · ")
            isFinished = true
        case .failed(let message):
            title = "parou com erro"
            compactText = "erro"
            detailText = message
            isFinished = true
        case .idle:
            title = "pronto"
            compactText = ""
            isFinished = true
        }
    }
}
