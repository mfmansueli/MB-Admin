import Foundation
import Observation

/// O que a última comparação entre duas lojas concluiu sobre cada produto — guardado pra "postar em
/// outra loja" (na aba publicados) avisar quando o produto já existe (ou pode existir) na loja de
/// destino, sem comparar de novo nem fazer chamada nenhuma. Só em memória: vale pras comparações
/// feitas desde que o app abriu; sem comparação entre as duas lojas, simplesmente não há aviso.
///
/// Guardado nos dois sentidos (A → B e B → A), cada um chaveado pelo produto da loja de origem:
/// quem pergunta está sempre olhando um produto da própria loja e quer saber da outra.
///
/// Só o que está publicado conta (`PublishedListingFilter`): quando um anúncio sai da vitrine depois
/// da comparação (`forgetUnpublished`), ele deixa de provar que o produto existe na loja dele — um
/// produto cujo único par era esse passa a "possivelmente ausente" lá (ou "não verificado", se a lista
/// de lá não veio inteira) — e deixa de ter aviso como origem.
@MainActor
@Observable
final class ComparisonMatchMemory {
    private nonisolated struct DirectedPair: Hashable, Sendable {
        let source: EnjoeiAccountID
        let destination: EnjoeiAccountID
    }

    /// O que se sabe de um produto da origem no destino: com quais anúncios de lá ele tem par (forte ou
    /// em revisão) e o que sobra sem eles.
    private nonisolated struct Entry: Sendable {
        /// Sem par nenhum: possivelmente ausente, outra versão ou não verificado.
        var withoutPair: ComparisonPresence
        /// Anúncios do destino com par forte/confirmado com este.
        var present: Set<Int> = []
        /// Anúncios do destino em revisão com este.
        var possible: Set<Int> = []

        var presence: ComparisonPresence {
            if !present.isEmpty { return .present }
            if !possible.isEmpty { return max(.possible, withoutPair) }
            return withoutPair
        }
    }

    private var entries: [DirectedPair: [Int: Entry]] = [:]

    /// Troca o que estava guardado pro par de lojas inteiro (nos dois sentidos) pelo resultado novo
    /// — é sempre "a última comparação" que vale, inclusive pra esquecer um par que deixou de casar.
    func record(_ result: AccountComparisonResult, accountA: EnjoeiAccountID, accountB: EnjoeiAccountID) {
        // Sem par na outra loja: ausente se a lista de lá veio inteira, senão não dá pra dizer.
        let fallbackA: ComparisonPresence = result.storeB.status.allowsAbsenceConclusions ? .possiblyMissing : .unverified
        let fallbackB: ComparisonPresence = result.storeA.status.allowsAbsenceConclusions ? .possiblyMissing : .unverified
        var fromA: [Int: Entry] = [:]
        var fromB: [Int: Entry] = [:]
        func mark(_ table: inout [Int: Entry], _ productID: Int, _ presence: ComparisonPresence) {
            var entry = table[productID] ?? Entry(withoutPair: presence)
            entry.withoutPair = max(entry.withoutPair, presence)
            table[productID] = entry
        }
        func pair(_ table: inout [Int: Entry], _ productID: Int, fallback: ComparisonPresence, with other: Int, present: Bool) {
            var entry = table[productID] ?? Entry(withoutPair: fallback)
            if present { entry.present.insert(other) } else { entry.possible.insert(other) }
            table[productID] = entry
        }
        func missing(_ product: EnjoeiProduct, sellerID: Int) -> ComparisonPresence {
            result.otherVersions[ListingKey(sellerID: sellerID, productID: product.id)]?.isEmpty == false ? .otherVersion : .possiblyMissing
        }
        for product in result.possiblyMissingInB { mark(&fromA, product.id, missing(product, sellerID: result.storeA.sellerID)) }
        for product in result.possiblyMissingInA { mark(&fromB, product.id, missing(product, sellerID: result.storeB.sellerID)) }
        for listing in result.unverifiedA { mark(&fromA, listing.product.id, .unverified) }
        for listing in result.unverifiedB { mark(&fromB, listing.product.id, .unverified) }
        for match in result.reviews {
            pair(&fromA, match.productA.id, fallback: fallbackA, with: match.productB.id, present: false)
            pair(&fromB, match.productB.id, fallback: fallbackB, with: match.productA.id, present: false)
        }
        for match in result.matches {
            pair(&fromA, match.productA.id, fallback: fallbackA, with: match.productB.id, present: true)
            pair(&fromB, match.productB.id, fallback: fallbackB, with: match.productA.id, present: true)
        }
        entries[DirectedPair(source: accountA, destination: accountB)] = fromA
        entries[DirectedPair(source: accountB, destination: accountA)] = fromB
    }

    /// O que a última comparação entre as duas lojas diz sobre o produto `productID` (da loja
    /// `source`) na loja `destination` — `nil` sem comparação entre as duas.
    func presence(of productID: Int, from source: EnjoeiAccountID, to destination: EnjoeiAccountID) -> ComparisonPresence? {
        entries[DirectedPair(source: source, destination: destination)]?[productID]?.presence
    }

    /// Os anúncios saíram da vitrine da conta (inativados, apagados): deixam de ser par de qualquer
    /// produto das outras lojas, e deixam de ter aviso como origem. Vale pras comparações já
    /// guardadas — uma comparação nova já vem sem eles.
    func forgetUnpublished(_ productIDs: Set<Int>, in accountID: EnjoeiAccountID) {
        guard !productIDs.isEmpty else { return }
        for key in Array(entries.keys) {
            if key.source == accountID {
                entries[key] = entries[key]?.filter { !productIDs.contains($0.key) }
            } else if key.destination == accountID {
                entries[key] = entries[key]?.mapValues { entry in
                    guard !entry.present.isDisjoint(with: productIDs) || !entry.possible.isDisjoint(with: productIDs) else { return entry }
                    var entry = entry
                    entry.present.subtract(productIDs)
                    entry.possible.subtract(productIDs)
                    return entry
                }
            }
        }
    }

    /// Esquece tudo que envolve a conta — chamado quando ela sai do app.
    func forget(accountID: EnjoeiAccountID) {
        entries = entries.filter { $0.key.source != accountID && $0.key.destination != accountID }
    }
}
