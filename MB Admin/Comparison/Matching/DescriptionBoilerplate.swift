import Foundation

/// O texto padrão que a loja repete na descrição de quase todo anúncio ("prata 925 legítima, envio
/// em 24h, acompanha certificado…"). Igual em todo anúncio, não diz qual produto é — e duas lojas do
/// mesmo dono costumam ter o mesmo, o que deixaria toda descrição "quase igual" à da outra loja. Sai
/// da comparação de texto (as palavras do anúncio e a parcela da descrição no índice); os atributos
/// de versão continuam lidos da descrição inteira.
nonisolated enum DescriptionBoilerplate {
    private typealias Limits = MatchIndexParameters

    /// As duas lojas sem o texto padrão — o de cada uma e o das duas juntas (numa delas pode haver
    /// poucos templates buscados, e o texto padrão das duas costuma ser o mesmo). Determinístico: lê
    /// sempre a descrição original, então rodar de novo sobre o resultado não muda nada.
    static func removing(from sideA: ComparisonSide, _ sideB: ComparisonSide) -> (a: ComparisonSide, b: ComparisonSide) {
        let descriptionsA = sideA.listings.map(\.descriptionTokens).filter { !$0.isEmpty }
        let descriptionsB = sideB.listings.map(\.descriptionTokens).filter { !$0.isEmpty }
        let boilerplate = common(in: descriptionsA)
            .union(common(in: descriptionsB))
            .union(common(in: descriptionsA + descriptionsB))
        guard !boilerplate.isEmpty else { return (sideA, sideB) }
        return (stripped(sideA, boilerplate), stripped(sideB, boilerplate))
    }

    /// As palavras que aparecem em pelo menos `boilerplateMinimumShare` das descrições.
    static func common(in descriptions: [Set<String>]) -> Set<String> {
        guard descriptions.count >= Limits.boilerplateMinimumListings else { return [] }
        var counts: [String: Int] = [:]
        for words in descriptions {
            for word in words { counts[word, default: 0] += 1 }
        }
        let minimum = Int((Double(descriptions.count) * Limits.boilerplateMinimumShare).rounded(.up))
        return Set(counts.compactMap { $0.value >= minimum ? $0.key : nil })
    }

    private static func stripped(_ side: ComparisonSide, _ boilerplate: Set<String>) -> ComparisonSide {
        ComparisonSide(
            sellerID: side.sellerID,
            name: side.name,
            listings: side.listings.map { $0.removingBoilerplate(boilerplate) },
            status: side.status
        )
    }
}
