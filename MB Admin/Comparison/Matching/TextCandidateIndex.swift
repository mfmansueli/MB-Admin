import Foundation

/// Candidatos só pelo texto (Jaccard de título + descrição), com índice invertido — só pares que
/// já dividem pelo menos uma palavra chegam a calcular interseção/união.
///
/// Texto sozinho nunca confirma par: estes candidatos só servem pra revisão (ou pra não chamar de
/// "ausente" um produto cujas fotos falharam). Pra um título genérico ("brinco prata 925") não
/// casar com metade da loja, um par só sobrevive se estiver entre os `maxPerListing` melhores dos
/// **dois** lados.
nonisolated enum TextCandidateIndex {
    nonisolated struct Candidate: Equatable, Sendable {
        let indexA: Int
        let indexB: Int
        let score: Double
    }

    static func candidates(
        wordsA: [Set<String>],
        wordsB: [Set<String>],
        threshold: Double = PhotoMatchingParameters.textCandidateThreshold,
        maxPerListing: Int = PhotoMatchingParameters.maximumTextCandidatesPerListing
    ) -> [Candidate] {
        var indexByWord: [String: [Int]] = [:]
        for (indexB, words) in wordsB.enumerated() {
            for word in words {
                indexByWord[word, default: []].append(indexB)
            }
        }

        var all: [Candidate] = []
        for (indexA, wordsOfA) in wordsA.enumerated() where !wordsOfA.isEmpty {
            var shared: [Int: Int] = [:]
            for word in wordsOfA {
                for indexB in indexByWord[word] ?? [] {
                    shared[indexB, default: 0] += 1
                }
            }
            for (indexB, intersection) in shared {
                let union = wordsOfA.count + wordsB[indexB].count - intersection
                let score = Double(intersection) / Double(union)
                if score >= threshold {
                    all.append(Candidate(indexA: indexA, indexB: indexB, score: score))
                }
            }
        }
        return mutualTop(all, maxPerListing: maxPerListing)
    }

    /// Fica só o que está entre os `maxPerListing` melhores de A **e** de B. Empate desempatado
    /// pelos índices, pra o resultado sair sempre igual.
    private static func mutualTop(_ candidates: [Candidate], maxPerListing: Int) -> [Candidate] {
        func ranked(_ group: [Candidate]) -> [Candidate] {
            group.sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB)
            }
        }
        var topOfA: Set<[Int]> = []
        for group in Dictionary(grouping: candidates, by: \.indexA).values {
            for candidate in ranked(group).prefix(maxPerListing) {
                topOfA.insert([candidate.indexA, candidate.indexB])
            }
        }
        var result: [Candidate] = []
        for group in Dictionary(grouping: candidates, by: \.indexB).values {
            for candidate in ranked(group).prefix(maxPerListing) where topOfA.contains([candidate.indexA, candidate.indexB]) {
                result.append(candidate)
            }
        }
        return result.sorted { ($0.indexA, $0.indexB) < ($1.indexA, $1.indexB) }
    }
}
