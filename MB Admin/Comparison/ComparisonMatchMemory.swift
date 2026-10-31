import Foundation
import Observation

/// Os pares que a última comparação entre duas lojas achou — guardados pra "postar em outra loja"
/// (na aba publicados) avisar quando o produto talvez já exista na loja de destino, sem precisar
/// comparar de novo nem fazer chamada nenhuma. Só em memória: vale pras comparações feitas desde
/// que o app abriu; sem comparação entre as duas lojas, simplesmente não há aviso.
///
/// Guardado nos dois sentidos (A → B e B → A), cada um chaveado pelo produto da loja de origem:
/// quem pergunta está sempre olhando um produto da própria loja e quer saber da outra.
@MainActor
@Observable
final class ComparisonMatchMemory {
    private nonisolated struct DirectedPair: Hashable, Sendable {
        let source: EnjoeiAccountID
        let destination: EnjoeiAccountID
    }

    /// Similaridade (0 a 1) do par de cada produto da origem com um da loja de destino.
    private var similarities: [DirectedPair: [Int: Double]] = [:]

    /// Abaixo disso a comparação nem mostra o par (`AccountProductMatcher.defaultThreshold`) — e o
    /// aviso também não vale.
    static let warningThreshold = AccountProductMatcher.defaultThreshold

    /// Troca o que estava guardado pro par de lojas inteiro (nos dois sentidos) pelo resultado novo
    /// — é sempre "a última comparação" que vale, inclusive pra esquecer um par que deixou de casar.
    func record(_ matches: [ProductMatch], accountA: EnjoeiAccountID, accountB: EnjoeiAccountID) {
        var fromA: [Int: Double] = [:]
        var fromB: [Int: Double] = [:]
        for match in matches where match.similarity >= Self.warningThreshold {
            fromA[match.productA.id] = max(fromA[match.productA.id] ?? 0, match.similarity)
            fromB[match.productB.id] = max(fromB[match.productB.id] ?? 0, match.similarity)
        }
        similarities[DirectedPair(source: accountA, destination: accountB)] = fromA
        similarities[DirectedPair(source: accountB, destination: accountA)] = fromB
    }

    /// Quanto o produto `productID` (da loja `source`) se parece com algum da loja `destination`,
    /// pela última comparação entre as duas — `nil` sem comparação, ou sem par parecido o bastante.
    func similarity(of productID: Int, from source: EnjoeiAccountID, to destination: EnjoeiAccountID) -> Double? {
        similarities[DirectedPair(source: source, destination: destination)]?[productID]
    }

    /// Esquece tudo que envolve a conta — chamado quando ela sai do app.
    func forget(accountID: EnjoeiAccountID) {
        similarities = similarities.filter { $0.key.source != accountID && $0.key.destination != accountID }
    }
}
