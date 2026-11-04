import Foundation

/// Compara os anúncios de duas lojas: monta a evidência (fotos, texto) e resolve os estados. Puro e
/// síncrono — quem chama da tela usa `resolveOffMain`, que roda fora do MainActor.
///
/// A evidência é sempre da listagem inteira; resolver recorta antes só os anúncios publicados
/// (`PublishedSubset`) — o que saiu da vitrine depois da listagem não conta pra nada.
nonisolated enum AccountProductMatcher {
    static func compare(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        decisions: [ComparisonDecision] = [],
        runID: UUID = UUID(),
        unpublishedA: Set<Int> = [],
        unpublishedB: Set<Int> = []
    ) -> AccountComparisonResult {
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        let evidence = ComparisonEvidenceBuilder.build(sides.a.listings, sides.b.listings)
        let published = PublishedSubset.restrict(sides.a, sides.b, evidence: evidence, unpublishedA: unpublishedA, unpublishedB: unpublishedB)
        return ComparisonResolver.resolve(published.sideA, published.sideB, evidence: published.evidence, decisions: decisions, runID: runID)
    }

    /// Monta a evidência fora do MainActor — o único passo caro (fotos de A × fotos de B).
    @concurrent
    static func buildEvidenceOffMain(_ sideA: ComparisonSide, _ sideB: ComparisonSide) async -> ComparisonEvidenceBuilder.Output {
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        return ComparisonEvidenceBuilder.build(sides.a.listings, sides.b.listings)
    }

    /// - Parameters:
    ///   - evidence: de `buildEvidenceOffMain`, sobre as mesmas listas inteiras.
    ///   - unpublishedA: ids dos produtos de A que saíram da vitrine depois da listagem
    ///     (`PublishedListingFilter`) — ficam fora do resultado.
    ///   - unpublishedB: os de B.
    @concurrent
    // swiftlint:disable:next function_parameter_count
    static func resolveOffMain(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        evidence: ComparisonEvidenceBuilder.Output,
        unpublishedA: Set<Int> = [],
        unpublishedB: Set<Int> = [],
        decisions: [ComparisonDecision],
        runID: UUID,
        revision: Int
    ) async -> AccountComparisonResult {
        // O texto padrão sai da lista inteira, como na evidência — senão a semelhança de texto da
        // evidência e a do resolver discordariam depois do recorte.
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        let published = PublishedSubset.restrict(sides.a, sides.b, evidence: evidence, unpublishedA: unpublishedA, unpublishedB: unpublishedB)
        return ComparisonResolver.resolve(
            published.sideA, published.sideB, evidence: published.evidence, decisions: decisions, runID: runID, revision: revision
        )
    }

    /// Título sozinho, ou título + descrição quando o template já foi buscado — mais texto em comum
    /// entre dois anúncios do mesmo produto. `ProductMatchDifference` usa o mesmo texto pra explicar
    /// um par.
    static func comparableText(for product: EnjoeiProduct) -> String {
        guard let description = product.description, !description.isEmpty else { return product.title }
        return "\(product.title) \(description)"
    }
}
