import Foundation

/// Resultado de comparar duas lojas, em quatro estados que nunca se confundem:
/// - `matches`: correspondência forte (mesma foto, sem concorrente) ou confirmada por você;
/// - `reviews`: precisa revisar — há indício, mas não dá pra concluir sozinho;
/// - `possiblyMissingInB`/`possiblyMissingInA`: nenhum indício na outra loja, com tudo dos dois
///   lados analisado e a lista da outra loja completa;
/// - `unverifiedA`/`unverifiedB`: sem par, mas algo impediu a verificação — nunca é "ausente".
///
/// `rejected` são os pares que você marcou como produtos diferentes (pra poder desfazer).
///
/// Por cima dos estados, `families` agrupa os anúncios que dividem a mesma foto em versões (aro,
/// banho, cor, medida) com onde cada versão está, e `otherVersions` diz, de um possivelmente
/// ausente, quais versões dele a outra loja tem. `duplicatesA`/`duplicatesB` são o mesmo produto
/// cadastrado mais de uma vez dentro de cada loja (`StoreDuplicateFinder`). `learning` diz o que as
/// suas revisões decidiram sozinhas em outros pares (`ReviewLearning`).
nonisolated struct AccountComparisonResult: Equatable, Sendable {
    /// Da rodada de comparação — não muda quando uma revisão manual recalcula o resultado (só
    /// `revision`), pra tela não perder busca/filtro a cada decisão. Comparar de novo gera outro.
    let id: UUID
    let revision: Int
    let storeA: ComparisonStoreSummary
    let storeB: ComparisonStoreSummary
    let matches: [ProductMatch]
    let reviews: [ProductMatch]
    let rejected: [ProductMatch]
    /// Produtos de A sem nenhum indício em B.
    let possiblyMissingInB: [EnjoeiProduct]
    /// Produtos de B sem nenhum indício em A.
    let possiblyMissingInA: [EnjoeiProduct]
    let unverifiedA: [UnverifiedListing]
    let unverifiedB: [UnverifiedListing]
    /// Revisões manuais que deixaram de valer porque um dos anúncios mudou.
    let staleDecisionCount: Int
    /// Produtos com versões (mesma foto em vários anúncios, ou atributos que discordam).
    let families: [ProductFamily]
    /// De cada possivelmente ausente (das duas lojas) que tem outra versão na outra loja: quais.
    let otherVersions: [ListingKey: [OtherVersion]]
    /// Anúncios com par mas de uma família de versões, sem o template buscado — a etapa 2 da
    /// comparação busca o template deles também, pra conferir a versão pela descrição.
    let keysWantingDetails: Set<ListingKey>
    /// O mesmo produto cadastrado mais de uma vez na loja A (repetidos e talvez repetidos).
    let duplicatesA: [StoreDuplicateGroup]
    /// O mesmo na loja B.
    let duplicatesB: [StoreDuplicateGroup]
    /// Grupos das duas lojas que você marcou como não repetidos (pra poder desfazer).
    let dismissedDuplicates: [StoreDuplicateGroup]
    /// Onde as suas revisões põem a fronteira do índice, e quantos pares ela decidiu nesta rodada.
    let learning: ReviewLearning

    init(
        id: UUID = UUID(),
        revision: Int = 0,
        storeA: ComparisonStoreSummary,
        storeB: ComparisonStoreSummary,
        matches: [ProductMatch] = [],
        reviews: [ProductMatch] = [],
        rejected: [ProductMatch] = [],
        possiblyMissingInB: [EnjoeiProduct] = [],
        possiblyMissingInA: [EnjoeiProduct] = [],
        unverifiedA: [UnverifiedListing] = [],
        unverifiedB: [UnverifiedListing] = [],
        staleDecisionCount: Int = 0,
        families: [ProductFamily] = [],
        otherVersions: [ListingKey: [OtherVersion]] = [:],
        keysWantingDetails: Set<ListingKey> = [],
        duplicatesA: [StoreDuplicateGroup] = [],
        duplicatesB: [StoreDuplicateGroup] = [],
        dismissedDuplicates: [StoreDuplicateGroup] = [],
        learning: ReviewLearning = .none
    ) {
        self.id = id
        self.revision = revision
        self.storeA = storeA
        self.storeB = storeB
        self.matches = matches
        self.reviews = reviews
        self.rejected = rejected
        self.possiblyMissingInB = possiblyMissingInB
        self.possiblyMissingInA = possiblyMissingInA
        self.unverifiedA = unverifiedA
        self.unverifiedB = unverifiedB
        self.staleDecisionCount = staleDecisionCount
        self.families = families
        self.otherVersions = otherVersions
        self.keysWantingDetails = keysWantingDetails
        self.duplicatesA = duplicatesA
        self.duplicatesB = duplicatesB
        self.dismissedDuplicates = dismissedDuplicates
        self.learning = learning
    }

    var unverifiedCount: Int { unverifiedA.count + unverifiedB.count }
    var duplicateCount: Int { duplicatesA.count + duplicatesB.count }
    var hasProblems: Bool { !storeA.problems.isEmpty || !storeB.problems.isEmpty }

    /// Um anúncio está no resultado como par (forte/confirmado)?
    func isMatched(_ key: ListingKey) -> Bool {
        matches.contains { $0.keyA == key || $0.keyB == key }
    }
}
