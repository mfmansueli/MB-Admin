import Foundation

/// Anúncios da **mesma** loja que são o mesmo produto cadastrado mais de uma vez — a mesma foto (ou o
/// mesmo arquivo), o mesmo título base e nenhum aro, banho, cor da pedra, medida, marca ou categoria
/// em conflito. Versões (aro 16 × aro 18 com a mesma foto) nunca entram aqui: são família
/// (`ProductFamily`).
nonisolated struct StoreDuplicateGroup: Identifiable, Equatable, Sendable {
    nonisolated enum Status: Sendable {
        /// A mesma foto, sem nenhuma dúvida, com o template dos dois conferido.
        case repeated
        /// Você confirmou que são repetidos.
        case confirmed
        /// Há indício, mas falta conferir algo (template não buscado, preço bem diferente, foto só
        /// parecida…).
        case possible
        /// Você marcou que não são repetidos (ex.: duas unidades do mesmo produto de propósito).
        case dismissed
    }

    let sellerID: Int
    let storeName: String
    /// Do mais antigo pro mais novo (pelo id do anúncio).
    let products: [EnjoeiProduct]
    let status: Status
    /// O que liga os anúncios e, em "talvez", o que falta.
    let reasons: [DuplicateReason]
    /// O índice do par mais fraco do grupo — o quanto o grupo inteiro se sustenta.
    let index: MatchIndex
    /// A foto que liga os anúncios (a capa do primeiro, sem ela).
    let photoPublicID: String?
    /// Os pares de anúncios que formam o grupo — o que uma revisão manual grava.
    let pairKeys: [ListingPairKey]

    var id: String {
        let kind = status == .dismissed ? "nao-repetidos" : "repetidos"
        return "\(kind)-\(sellerID)-\(products.first?.id ?? 0)"
    }

    var keys: [ListingKey] { products.map { ListingKey(sellerID: sellerID, productID: $0.id) } }
    var title: String { products.first?.title ?? "" }
    var hasUserDecision: Bool { status == .confirmed || status == .dismissed }
    /// Repetido sem dúvida, ou confirmado por você — dá pra escolher um e apagar os outros
    /// (`DuplicateCleanup`).
    var isCertain: Bool { status == .repeated || status == .confirmed }

    /// "repetido 2 vezes" / "talvez repetidos" — o estado em poucas palavras.
    var statusText: String {
        switch status {
        case .repeated, .confirmed: "\(products.count) anúncios iguais"
        case .possible: "talvez repetidos (\(products.count) anúncios)"
        case .dismissed: "não são repetidos (\(products.count) anúncios)"
        }
    }

    /// A evidência e, em "talvez", a dúvida principal — numa linha só.
    var summaryText: String {
        let doubts = reasons.filter(\.isDoubt)
        if status == .possible, let doubt = doubts.first { return doubt.text }
        return reasons.filter { !$0.isDoubt }.map(\.text).joined(separator: " · ")
    }

    func matchesSearch(_ text: String) -> Bool {
        products.contains { $0.title.localizedCaseInsensitiveContains(text) }
    }

    func product(for key: ListingKey) -> EnjoeiProduct? {
        guard key.sellerID == sellerID else { return nil }
        return products.first { $0.id == key.productID }
    }
}
