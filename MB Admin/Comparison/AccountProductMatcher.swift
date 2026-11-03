import Foundation

/// Compara os anúncios de duas lojas: monta a evidência (fotos, texto) e resolve os estados. Puro e
/// síncrono — quem chama da tela usa `resolveOffMain`, que roda fora do MainActor.
nonisolated enum AccountProductMatcher {
    static func compare(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        decisions: [ComparisonDecision] = [],
        runID: UUID = UUID()
    ) -> AccountComparisonResult {
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        let evidence = ComparisonEvidenceBuilder.build(sides.a.listings, sides.b.listings)
        return ComparisonResolver.resolve(sides.a, sides.b, evidence: evidence, decisions: decisions, runID: runID)
    }

    /// Monta a evidência fora do MainActor — o único passo caro (fotos de A × fotos de B).
    @concurrent
    static func buildEvidenceOffMain(_ sideA: ComparisonSide, _ sideB: ComparisonSide) async -> ComparisonEvidenceBuilder.Output {
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        return ComparisonEvidenceBuilder.build(sides.a.listings, sides.b.listings)
    }

    @concurrent
    // swiftlint:disable:next function_parameter_count
    static func resolveOffMain(
        _ sideA: ComparisonSide,
        _ sideB: ComparisonSide,
        evidence: ComparisonEvidenceBuilder.Output,
        decisions: [ComparisonDecision],
        runID: UUID,
        revision: Int
    ) async -> AccountComparisonResult {
        let sides = DescriptionBoilerplate.removing(from: sideA, sideB)
        return ComparisonResolver.resolve(sides.a, sides.b, evidence: evidence, decisions: decisions, runID: runID, revision: revision)
    }

    /// Título sozinho, ou título + descrição quando o template já foi buscado — mais texto em comum
    /// entre dois anúncios do mesmo produto. `ProductMatchDifference` usa o mesmo texto pra explicar
    /// um par.
    static func comparableText(for product: EnjoeiProduct) -> String {
        guard let description = product.description, !description.isEmpty else { return product.title }
        return "\(product.title) \(description)"
    }
}
