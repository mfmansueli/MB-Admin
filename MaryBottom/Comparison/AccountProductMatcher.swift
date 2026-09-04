import Foundation

/// Casa os produtos de duas contas pelo título, sem depender dos ids baterem (nunca batem — são
/// contas diferentes) nem do título ser idêntico.
nonisolated enum AccountProductMatcher {
    /// A partir de que similaridade um par vira "o mesmo produto" pro resultado — ponto de partida
    /// razoável, não uma calibração científica; o `%` de cada par fica visível na tela pra quem usa
    /// julgar.
    static let defaultThreshold = 0.5

    /// Compara todo produto de A com todo produto de B, e casa cada um com no máximo um par do
    /// outro lado — casamento guloso pelo maior score primeiro, pra dois produtos de A parecidos
    /// com o mesmo produto de B não ficarem os dois "casados" com ele.
    static func compare(
        productsA: [EnjoeiProduct],
        productsB: [EnjoeiProduct],
        threshold: Double = defaultThreshold
    ) -> AccountComparisonResult {
        // Tokeniza uma vez por produto, não uma vez por par — O(N+M) em vez de O(N×M) tokenizações.
        let tokensA = productsA.map { ($0, ProductSimilarity.tokenize($0.title)) }
        let tokensB = productsB.map { ($0, ProductSimilarity.tokenize($0.title)) }

        // Índice invertido — cada palavra de B aponta pros índices dos produtos que a contêm.
        // Sem isso, o laço abaixo calculava interseção/união pra TODO par (A×B) só pra descartar a
        // esmagadora maioria por não compartilhar palavra nenhuma (`intersection > 0`) — numa loja
        // variada, isso é praticamente todos os pares. Com o índice, só os pares que já sabemos
        // compartilhar pelo menos uma palavra chegam a calcular interseção/união de verdade; o
        // resultado final é idêntico (mesmos pares passavam pelo `guard intersection > 0` de
        // qualquer jeito), só sem o trabalho descartado.
        var indexByWord: [String: [Int]] = [:]
        for (indexB, (_, wordsB)) in tokensB.enumerated() {
            for word in wordsB {
                indexByWord[word, default: []].append(indexB)
            }
        }

        var candidates: [(indexA: Int, indexB: Int, score: Double)] = []
        for (indexA, (_, wordsA)) in tokensA.enumerated() {
            guard !wordsA.isEmpty else { continue }
            var candidateIndicesB: Set<Int> = []
            for word in wordsA {
                if let matches = indexByWord[word] {
                    candidateIndicesB.formUnion(matches)
                }
            }
            for indexB in candidateIndicesB {
                let wordsB = tokensB[indexB].1
                let intersection = wordsA.intersection(wordsB).count
                guard intersection > 0 else { continue }
                let union = wordsA.union(wordsB).count
                let score = Double(intersection) / Double(union)
                guard score >= threshold else { continue }
                candidates.append((indexA, indexB, score))
            }
        }

        // Maior score primeiro; empate desempatado pelos ids, só pra ordem sair determinística
        // (e portanto testável) mesmo quando dois pares empatam.
        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if productsA[$0.indexA].id != productsA[$1.indexA].id {
                return productsA[$0.indexA].id < productsA[$1.indexA].id
            }
            return productsB[$0.indexB].id < productsB[$1.indexB].id
        }

        var usedA: Set<Int> = []
        var usedB: Set<Int> = []
        var matches: [ProductMatch] = []
        for candidate in candidates {
            guard !usedA.contains(candidate.indexA), !usedB.contains(candidate.indexB) else { continue }
            usedA.insert(candidate.indexA)
            usedB.insert(candidate.indexB)
            matches.append(
                ProductMatch(
                    productA: productsA[candidate.indexA],
                    productB: productsB[candidate.indexB],
                    similarity: candidate.score
                )
            )
        }

        let onlyInA = productsA.enumerated().filter { !usedA.contains($0.offset) }.map(\.element)
        let onlyInB = productsB.enumerated().filter { !usedB.contains($0.offset) }.map(\.element)

        return AccountComparisonResult(matches: matches, onlyInA: onlyInA, onlyInB: onlyInB)
    }
}
