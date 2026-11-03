import SwiftUI

/// Uma linha de "repetidos em loja X": o mesmo produto cadastrado mais de uma vez na mesma loja — a
/// foto, o título, quantos anúncios, o que liga os anúncios (ou, em "talvez", o que falta conferir), o
/// índice do par mais fraco e uma linha por anúncio (preço, número, abrir no Enjoei, e se ele está na
/// fila pra ser apagado). Em "talvez", os dois botões de decidir ficam numa faixa embaixo; um grupo
/// revisado por você tem "desfazer". "Não são repetidos" num grupo certo (duas unidades de propósito,
/// por exemplo) fica no menu de contexto.
///
/// Num grupo certo, "escolher qual manter" entra na seleção já com este grupo marcado. Na seleção,
/// cada anúncio vira uma escolha: o que fica ("manter") e os que vão pra fila pra serem apagados —
/// tocar num anúncio troca qual fica (`DuplicateCleanup`).
struct StoreDuplicateRowView: View, Equatable {
    let group: StoreDuplicateGroup
    /// Só dos anúncios deste grupo.
    var states: [Int: DuplicateListingState] = [:]
    var isSelecting = false
    var isSelected = false
    /// O anúncio que fica, quando o grupo dá pra limpar (`DuplicateCleanup.kept`).
    var keptID: Int?
    var onDecide: (ComparisonDecision.Verdict) -> Void = { _ in }
    var onUndo: () -> Void = {}
    var onChooseKept: () -> Void = {}
    var onToggleSelection: () -> Void = {}
    var onKeep: (Int) -> Void = { _ in }

    /// Só o que a linha mostra — os closures são recriados a cada render da lista.
    static func == (lhs: StoreDuplicateRowView, rhs: StoreDuplicateRowView) -> Bool {
        lhs.group == rhs.group && lhs.states == rhs.states && lhs.isSelecting == rhs.isSelecting
            && lhs.isSelected == rhs.isSelected && lhs.keptID == rhs.keptID
    }

    private var isSelectable: Bool { DuplicateCleanup.isSelectable(group, states: states) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                selectionIndicator
                    .opacity(isSelectable ? 1 : 0)
                    .padding(.top, 14)
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área no Mac Catalyst — ver
        // `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .contextMenu {
            if !isSelecting {
                contextMenuItems
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
                .contentShape(.rect)
                .onTapGesture {
                    if isSelecting, isSelectable { onToggleSelection() }
                }
            VStack(spacing: 6) {
                ForEach(group.products) { product in
                    listingRow(product)
                }
            }
            .padding(.leading, 52 + 12)
            if !isSelecting {
                actionButtons
            }
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var contextMenuItems: some View {
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

    private func listingRow(_ product: EnjoeiProduct) -> some View {
        let state = states[product.id] ?? .listed
        let choice = isSelecting && isSelectable && state.isListed ? keepChoice(for: product) : nil
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // O título só quando muda — o do grupo já está em cima.
                if product.title != group.title {
                    Text(product.title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .strikethrough(state == .deleted, color: .secondary)
                }
                Text([product.formattedPrice, "anúncio \(product.id)"].compactMap(\.self).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.supportingText)
                    .lineLimit(1)
                    .strikethrough(state == .deleted, color: .secondary)
                // O estado fica sem risco, pra ler fácil.
                if let text = state.text {
                    Text(text)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(stateStyle(state))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let choice {
                choiceLabel(choice)
            } else if !isSelecting {
                Link(destination: product.storePageURL) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.body)
                }
                .accessibilityLabel("abrir o anúncio \(product.id) no Enjoei")
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if choice != nil { onKeep(product.id) }
        }
        .accessibilityElement(children: choice == nil ? .contain : .combine)
        .accessibilityAddTraits(choice == nil ? [] : .isButton)
        .accessibilityIdentifier(choice == nil ? "" : "duplicateListing-\(product.id)")
        .accessibilityHint(choice == .delete ? "toque pra manter este no lugar dos outros" : "")
    }

    private enum KeepChoice {
        /// O anúncio que fica na loja.
        case keep
        /// Vai pra fila pra ser apagado (grupo marcado).
        case delete
        /// Grupo não marcado — ainda não vai nada pra fila.
        case other
    }

    private func keepChoice(for product: EnjoeiProduct) -> KeepChoice {
        if product.id == keptID { return .keep }
        return isSelected ? .delete : .other
    }

    @ViewBuilder
    private func choiceLabel(_ choice: KeepChoice) -> some View {
        switch choice {
        case .keep:
            Label("manter", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.statusSuccess)
        case .delete:
            Label("apagar", systemImage: "trash")
                .foregroundStyle(Color.statusFailure)
        case .other:
            Label("manter este", systemImage: "circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
        }
    }

    private func stateStyle(_ state: DuplicateListingState) -> Color {
        switch state {
        case .failed: .statusFailure
        case .deleted: .statusSuccess
        case .listed, .queued, .deleting: .secondary
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isSelected ? AnyShapeStyle(Color.onTint) : AnyShapeStyle(Color(uiColor: .tertiaryLabel)),
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear)
            )
            .accessibilityLabel(isSelected ? "selecionado" : "não selecionado")
            .onTapGesture {
                if isSelectable { onToggleSelection() }
            }
    }

    /// "talvez": as duas decisões. Grupo certo: "escolher qual manter" (com algo pra apagar) e, se
    /// você decidiu, "desfazer".
    @ViewBuilder
    private var actionButtons: some View {
        if group.status == .possible {
            buttonStrip {
                capsuleButton("são repetidos", systemImage: "equal.circle", accessibilityLabel: "são anúncios repetidos") {
                    onDecide(.sameProduct)
                }
                capsuleButton("não são", systemImage: "nosign", accessibilityLabel: "não são anúncios repetidos") {
                    onDecide(.differentProducts)
                }
            }
        } else if isSelectable || group.hasUserDecision {
            buttonStrip {
                if isSelectable {
                    capsuleButton("escolher qual manter", systemImage: "checkmark.circle", accessibilityLabel: "escolher qual anúncio manter") {
                        onChooseKept()
                    }
                }
                if group.hasUserDecision {
                    capsuleButton("desfazer", systemImage: "arrow.uturn.backward", accessibilityLabel: "desfazer a revisão destes anúncios") {
                        onUndo()
                    }
                }
            }
        }
    }

    /// Na largura da linha toda, como na revisão de um par entre lojas; um embaixo do outro só com
    /// letra muito grande.
    private func buttonStrip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { content }
            VStack(spacing: 8) { content }
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
