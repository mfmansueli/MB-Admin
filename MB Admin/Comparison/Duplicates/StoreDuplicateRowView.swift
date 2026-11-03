import SwiftUI

/// Uma linha de "repetidos em loja X": o mesmo produto cadastrado mais de uma vez na mesma loja — a
/// foto, o título, quantos anúncios, o que liga os anúncios (ou, em "talvez", o que falta conferir), o
/// índice do par mais fraco e uma linha por anúncio (preço, número, abrir no Enjoei). Em "talvez", os
/// dois botões de decidir ficam numa faixa embaixo; um grupo revisado por você tem "desfazer". "Não
/// são repetidos" num grupo certo (duas unidades de propósito, por exemplo) fica no menu de contexto.
struct StoreDuplicateRowView: View, Equatable {
    let group: StoreDuplicateGroup
    var onDecide: (ComparisonDecision.Verdict) -> Void = { _ in }
    var onUndo: () -> Void = {}

    /// Só o grupo decide se a linha muda — os closures são recriados a cada render da lista.
    static func == (lhs: StoreDuplicateRowView, rhs: StoreDuplicateRowView) -> Bool {
        lhs.group == rhs.group
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ProductPhotoView(
                    photoURL: group.photoPublicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .thumbnail) },
                    largePhotoURL: group.photoPublicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .card) },
                    title: group.title,
                    size: 52
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text("\(group.statusText) em \(group.storeName)")
                        .font(.subheadline)
                        .foregroundStyle(.supportingText)
                    if !group.summaryText.isEmpty {
                        Text(group.summaryText)
                            .font(.footnote)
                            .foregroundStyle(group.status == .possible ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if !group.index.components.isEmpty {
                    MatchIndexBadge(index: group.index)
                }
            }
            VStack(spacing: 6) {
                ForEach(group.products) { product in
                    listingRow(product)
                }
            }
            .padding(.leading, 52 + 12)
            if group.status == .possible {
                decisionButtons
            } else if group.hasUserDecision {
                undoButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área no Mac Catalyst — ver
        // `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            if group.status == .repeated {
                Button {
                    onDecide(.differentProducts)
                } label: {
                    Label("não são repetidos", systemImage: "nosign")
                }
            }
            ForEach(group.products) { product in
                ShareLink(item: product.storePageURL) {
                    Label("compartilhar o anúncio \(product.id)", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func listingRow(_ product: EnjoeiProduct) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // O título só quando muda — o do grupo já está em cima.
                if product.title != group.title {
                    Text(product.title)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Text([product.formattedPrice, "anúncio \(product.id)"].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.supportingText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Link(destination: product.storePageURL) {
                Image(systemName: "arrow.up.right.square")
                    .font(.body)
            }
            .accessibilityLabel("abrir o anúncio \(product.id) no Enjoei")
        }
    }

    /// Na largura da linha toda, como na revisão de um par entre lojas; um embaixo do outro só com
    /// letra muito grande.
    private var decisionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { decisionButtonPair }
            VStack(spacing: 8) { decisionButtonPair }
        }
    }

    @ViewBuilder private var decisionButtonPair: some View {
        capsuleButton("são repetidos", systemImage: "equal.circle", accessibilityLabel: "são anúncios repetidos") {
            onDecide(.sameProduct)
        }
        capsuleButton("não são", systemImage: "nosign", accessibilityLabel: "não são anúncios repetidos") {
            onDecide(.differentProducts)
        }
    }

    private var undoButton: some View {
        capsuleButton("desfazer", systemImage: "arrow.uturn.backward", accessibilityLabel: "desfazer a revisão destes anúncios") {
            onUndo()
        }
    }

    private func capsuleButton(_ title: String, systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
