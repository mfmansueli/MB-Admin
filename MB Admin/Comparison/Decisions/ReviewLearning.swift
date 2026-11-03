import Foundation

/// O que as suas revisões entre duas lojas ensinam sobre o índice de correspondência (`MatchIndex`):
/// onde, pelos pares que você já decidiu, começa o "mesmo produto" e termina o "diferentes". Cada
/// "mesmo produto"/"diferentes" vira um exemplo com o índice que o par tem hoje; os pares ainda em
/// "precisa revisar" que caem claramente de um lado da fronteira são decididos do mesmo jeito, com o
/// motivo dizendo que veio das suas revisões (e um toque corrige — a correção vira mais um exemplo).
///
/// - **"mesmo produto" a partir de** `sameFloor`: o menor índice que você confirmou **acima** de todo
///   par que você marcou como diferente, com pelo menos
///   `MatchIndexParameters.learnedVerdictMinimumDecisions` confirmações ali.
/// - **"diferentes" até** `differentCeiling`: o maior índice que você marcou como diferente **abaixo**
///   de todo par que você confirmou, com pelo menos o mesmo tanto de exemplos.
/// - Precisa das duas respostas: só com confirmações, não dá pra saber onde começa o "diferentes"
///   (e vice-versa). Entre os dois limites, nada muda — continua em revisão.
///
/// Versões (aro 16 × aro 18 confirmados por você como o mesmo anúncio) não entram como exemplo: o
/// índice delas é baixo pelo conflito de atributo, e esses pares nunca chegam a "precisa revisar".
nonisolated struct ReviewLearning: Equatable, Sendable {
    nonisolated struct Sample: Equatable, Sendable {
        let score: Int
        let verdict: ComparisonDecision.Verdict
    }

    /// Índice a partir do qual um par em revisão vira "mesmo produto".
    let sameFloor: Int?
    /// Índice até o qual um par em revisão vira "diferentes".
    let differentCeiling: Int?
    /// Quantas confirmações sustentam `sameFloor` (todas acima de qualquer "diferentes").
    let sameDecisions: Int
    /// Quantos "diferentes" sustentam `differentCeiling` (todos abaixo de qualquer confirmação).
    let differentDecisions: Int
    /// Pares que esta comparação decidiu assim — preenchido pelo `ComparisonResolver`.
    var learnedSame = 0
    var learnedDifferent = 0

    static let none = ReviewLearning(sameFloor: nil, differentCeiling: nil, sameDecisions: 0, differentDecisions: 0)

    static func learn(from samples: [Sample], minimumDecisions: Int = MatchIndexParameters.learnedVerdictMinimumDecisions) -> ReviewLearning {
        let same = samples.filter { $0.verdict == .sameProduct }.map(\.score)
        let different = samples.filter { $0.verdict == .differentProducts }.map(\.score)
        guard let highestDifferent = different.max(), let lowestSame = same.min() else { return .none }

        let sameAbove = same.filter { $0 > highestDifferent }
        let differentBelow = different.filter { $0 < lowestSame }
        let hasFloor = sameAbove.count >= minimumDecisions
        let hasCeiling = differentBelow.count >= minimumDecisions
        return ReviewLearning(
            sameFloor: hasFloor ? sameAbove.min() : nil,
            differentCeiling: hasCeiling ? differentBelow.max() : nil,
            sameDecisions: hasFloor ? sameAbove.count : 0,
            differentDecisions: hasCeiling ? differentBelow.count : 0
        )
    }

    /// O que as revisões dizem de um par com esse índice — `nil` na faixa em dúvida.
    func verdict(forScore score: Int) -> ComparisonDecision.Verdict? {
        if let sameFloor, score >= sameFloor { return .sameProduct }
        if let differentCeiling, score <= differentCeiling { return .differentProducts }
        return nil
    }

    var hasChanges: Bool { learnedSame + learnedDifferent > 0 }

    /// Um par em "precisa revisar", com os índices dos dois anúncios em cada loja.
    nonisolated struct Candidate: Sendable {
        let id: Int
        let indexA: Int
        let indexB: Int
        let score: Int
        /// Ligado por foto (a mesma, parecida ou em outra cor) — só texto nunca vira par aprendido.
        let isPhotoLink: Bool
    }

    /// O que as revisões decidem desses pares. "Mesmo produto" só com ligação por foto, quando nenhum
    /// dos dois anúncios já tem par e o par é o único candidato acima do limite de cada lado — dois
    /// candidatos pro mesmo anúncio continuam em revisão. "Diferentes" vale pra qualquer um abaixo.
    func verdicts(for candidates: [Candidate], matchedA: Set<Int>, matchedB: Set<Int>) -> [Int: ComparisonDecision.Verdict] {
        let promotable = candidates.filter { $0.isPhotoLink && verdict(forScore: $0.score) == .sameProduct }
        let countA = Dictionary(grouping: promotable, by: \.indexA).mapValues(\.count)
        let countB = Dictionary(grouping: promotable, by: \.indexB).mapValues(\.count)
        var verdicts: [Int: ComparisonDecision.Verdict] = [:]
        for candidate in promotable where countA[candidate.indexA] == 1 && countB[candidate.indexB] == 1
            && !matchedA.contains(candidate.indexA) && !matchedB.contains(candidate.indexB) {
            verdicts[candidate.id] = .sameProduct
        }
        for candidate in candidates where verdict(forScore: candidate.score) == .differentProducts {
            verdicts[candidate.id] = .differentProducts
        }
        return verdicts
    }
}
