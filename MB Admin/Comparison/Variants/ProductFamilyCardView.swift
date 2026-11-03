import SwiftUI

/// Um produto com várias versões (a mesma foto em vários anúncios): a foto, o título, o resumo
/// ("3 versões · 1 só em antonia") e uma linha por versão — "aro 16 · ródio" e onde ela está: nas
/// duas lojas, só numa, pra revisar ou não verificada. Pra postar uma versão que falta, a mesma
/// versão aparece em "possivelmente ausentes", com o botão.
struct ProductFamilyCardView: View {
    let family: ProductFamily
    let accountAName: String
    let accountBName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ProductPhotoView(
                    photoURL: family.photoPublicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .thumbnail) },
                    largePhotoURL: family.photoPublicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .card) },
                    title: family.title,
                    size: 52
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(family.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(family.summary(accountAName: accountAName, accountBName: accountBName))
                        .font(.footnote)
                        .foregroundStyle(.supportingText)
                    if !family.dimensions.isEmpty {
                        Text("muda: \(family.dimensions.map(\.label).joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 6) {
                ForEach(family.versions) { version in
                    versionRow(version)
                }
            }
            .padding(.leading, 52 + 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área no Mac Catalyst — ver
        // `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func versionRow(_ version: ProductFamilyVersion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(versionTitle(version))
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 8)
            Label(presenceText(version.presence), systemImage: presenceSymbol(version.presence))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(presenceColor(version.presence))
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// Sem eixo que mude (versões só de preço/texto), o título do anúncio.
    private func versionTitle(_ version: ProductFamilyVersion) -> String {
        guard version.label.isEmpty else { return version.label }
        return (version.productA ?? version.productB)?.title ?? ""
    }

    private func presenceText(_ presence: ProductFamilyVersion.Presence) -> String {
        switch presence {
        case .both: "nas duas"
        case .onlyInA: "só em \(accountAName)"
        case .onlyInB: "só em \(accountBName)"
        case .needsReview: "revisar"
        case .unverified: "não verificado"
        }
    }

    private func presenceSymbol(_ presence: ProductFamilyVersion.Presence) -> String {
        switch presence {
        case .both: "checkmark.circle.fill"
        case .onlyInA, .onlyInB: "circle.dashed"
        case .needsReview: "questionmark.circle"
        case .unverified: "exclamationmark.triangle"
        }
    }

    private func presenceColor(_ presence: ProductFamilyVersion.Presence) -> Color {
        switch presence {
        case .both: .statusSuccess
        case .onlyInA, .onlyInB: .statusInProgress
        case .needsReview: .primary
        case .unverified: .secondary
        }
    }
}
