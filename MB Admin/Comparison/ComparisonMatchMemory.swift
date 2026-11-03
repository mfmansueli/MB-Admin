import Foundation
import Observation

/// O que a última comparação entre duas lojas concluiu sobre cada produto — guardado pra "postar em
/// outra loja" (na aba publicados) avisar quando o produto já existe (ou pode existir) na loja de
/// destino, sem comparar de novo nem fazer chamada nenhuma. Só em memória: vale pras comparações
/// feitas desde que o app abriu; sem comparação entre as duas lojas, simplesmente não há aviso.
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

    private var presences: [DirectedPair: [Int: ComparisonPresence]] = [:]

    /// Troca o que estava guardado pro par de lojas inteiro (nos dois sentidos) pelo resultado novo
    /// — é sempre "a última comparação" que vale, inclusive pra esquecer um par que deixou de casar.
    func record(_ result: AccountComparisonResult, accountA: EnjoeiAccountID, accountB: EnjoeiAccountID) {
        var fromA: [Int: ComparisonPresence] = [:]
        var fromB: [Int: ComparisonPresence] = [:]
        func mark(_ table: inout [Int: ComparisonPresence], _ productID: Int, _ presence: ComparisonPresence) {
            table[productID] = max(table[productID] ?? .possiblyMissing, presence)
        }
        func missing(_ product: EnjoeiProduct, sellerID: Int) -> ComparisonPresence {
            result.otherVersions[ListingKey(sellerID: sellerID, productID: product.id)]?.isEmpty == false ? .otherVersion : .possiblyMissing
        }
        for product in result.possiblyMissingInB { mark(&fromA, product.id, missing(product, sellerID: result.storeA.sellerID)) }
        for product in result.possiblyMissingInA { mark(&fromB, product.id, missing(product, sellerID: result.storeB.sellerID)) }
        for listing in result.unverifiedA { mark(&fromA, listing.product.id, .unverified) }
        for listing in result.unverifiedB { mark(&fromB, listing.product.id, .unverified) }
        for match in result.reviews {
            mark(&fromA, match.productA.id, .possible)
            mark(&fromB, match.productB.id, .possible)
        }
        for match in result.matches {
            mark(&fromA, match.productA.id, .present)
            mark(&fromB, match.productB.id, .present)
        }
        presences[DirectedPair(source: accountA, destination: accountB)] = fromA
        presences[DirectedPair(source: accountB, destination: accountA)] = fromB
    }

    /// O que a última comparação entre as duas lojas diz sobre o produto `productID` (da loja
    /// `source`) na loja `destination` — `nil` sem comparação entre as duas.
    func presence(of productID: Int, from source: EnjoeiAccountID, to destination: EnjoeiAccountID) -> ComparisonPresence? {
        presences[DirectedPair(source: source, destination: destination)]?[productID]
    }

    /// Esquece tudo que envolve a conta — chamado quando ela sai do app.
    func forget(accountID: EnjoeiAccountID) {
        presences = presences.filter { $0.key.source != accountID && $0.key.destination != accountID }
    }
}
