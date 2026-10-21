import SwiftUI

/// Linha da lista de publicados: foto, título, preço e o que aconteceu com aquele produto na
/// rodada — inclui o botão de aplicar o desconto sugerido pelo megafone, quando o produto pede essa
/// decisão.
///
/// No iPhone a ponta direita mostra uma coisa só (o botão de desconto, o status da rodada ou o
/// menu "..."); no iPad/Mac, o status e o menu lado a lado. As mesmas ações do menu ficam também
/// num menu de contexto (toque longo / clique direito), pra continuarem à mão quando o "..." não
/// aparece.
struct MegaphoneRowView: View, Equatable {
    let item: MegaphoneItem
    let runner: MegaphoneRunner
    let account: AccountSession
    var isSelecting = false
    var isSelected = false
    /// Uma rodada em aberto (megafonando ou pausada) — no iPhone, troca o "..." dos produtos ainda
    /// na fila pelo relógio de "na fila".
    var isRoundActive = false
    /// É o produto que o laço está megafonando agora (`MegaphoneRunner.activeItemID`) — o resto do
    /// pedaço em voo também está `.megaphoning`, mas na tela continua "na fila" até chegar a vez.
    var isActive = false
    var isCompact = true
    var onToggleSelection: () -> Void = {}

    /// Comparação sob medida pro `.equatable()` de quem chama (`AccountPublishedTabView`) — sem
    /// ela, o SwiftUI decide se recria a linha comparando `item: MegaphoneItem` inteiro (structs
    /// `EnjoeiProduct`/`MegaphoneExposure` aninhados, com várias strings), o que um trace de CPU
    /// real (iPad, Time Profiler) mostrou como o maior custo da tela durante uma rodada — mesmo já
    /// publicando `progressSnapshot` em lote. `product` some da comparação de propósito: depois de
    /// carregado ele só muda por `MegaphoneRunner.applyDescription` (daí comparar `description`
    /// puro, não o produto inteiro), nunca por `setStatus`/`resetItemsForNewRound`. `deleteStatus`/
    /// `inactivateStatus`/`repostStatus` também somem — não vêm de `item`, vêm de `runner`/
    /// `accountsStore` lidos ao vivo dentro do `body` (`@Environment`/referência), então o
    /// `Observation` já invalida esta view sozinho quando qualquer um dos três muda, independente
    /// desta comparação.
    static func == (lhs: MegaphoneRowView, rhs: MegaphoneRowView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.item.status == rhs.item.status
            && lhs.item.exposure == rhs.item.exposure
            && lhs.item.product.description == rhs.item.product.description
            && lhs.isSelecting == rhs.isSelecting
            && lhs.isSelected == rhs.isSelected
            && lhs.isRoundActive == rhs.isRoundActive
            && lhs.isActive == rhs.isActive
            && lhs.isCompact == rhs.isCompact
    }

    @State private var isConfirmingApply = false
    @State private var isConfirmingRepost = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingInactivate = false
    @State private var isShowingErrorDetail = false
    @Environment(AccountsStore.self) private var accountsStore

    /// Reposta pela fila de ações compartilhada — mesmo `poster` que a comparação entre contas e
    /// os inativos usam, com origem e destino sendo essa própria conta.
    private var repostTarget: PostTarget { PostTarget(productID: item.id, destinationAccountID: account.id) }
    private var repostStatus: MegaphoneStatus { accountsStore.poster.statuses[repostTarget] ?? .pending }
    private var deleteStatus: MegaphoneStatus { runner.deleteStatuses[item.id] ?? .pending }
    private var inactivateStatus: MegaphoneStatus { runner.inactivateStatuses[item.id] ?? .pending }
    private var isDeleted: Bool { deleteStatus == .succeeded }
    private var isInactivated: Bool { inactivateStatus == .succeeded }
    private var isGone: Bool { isDeleted || isInactivated }
    private var isActionInFlight: Bool {
        repostStatus == .megaphoning || deleteStatus == .megaphoning || inactivateStatus == .megaphoning
    }
    /// Sendo megafonado agora de verdade: o da vez na rodada, ou uma ação avulsa (aplicar desconto)
    /// sem rodada nenhuma em aberto.
    private var isInFlight: Bool {
        item.status == .megaphoning && (isActive || !isRoundActive)
    }
    /// O desconto ainda está por decidir — o preço mostra pra onde vai ("R$ 799 → R$ 352") e a
    /// ponta direita vira o botão de aplicar.
    private var isAwaitingDiscount: Bool {
        !isGone && item.status == .pending && item.needsDiscountDecision
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                selectionIndicator
            }

            ProductPhotoView(product: item.product)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .productTitleFont()
                    .lineLimit(2)
                detailLine
            }

            Spacer(minLength: 8)

            trailingView
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, 8)
        // Fundo sólido (mesmo que igual ao da página) — sem isso, no Mac Catalyst o scroll do
        // mouse/trackpad só funciona em cima de conteúdo com pixel de verdade (a foto), porque a
        // `ScrollView`/`LazyVStack` (ver quem usa esta row) não tem `List` por baixo roteando o
        // gesto sozinha. `.contentShape` não resolve isso — é pra gesture recognizers de toque, o
        // scroll do mouse no Catalyst passa por outro caminho que precisa de uma camada desenhada.
        // O produto da vez ganha um véu da cor de "em andamento" por cima desse fundo.
        .background {
            ZStack {
                Rectangle().fill(.background)
                if isInFlight {
                    Rectangle().fill(Color.statusInProgress.opacity(0.07))
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
        }
        .contextMenu {
            if !isSelecting {
                actionsMenuContent
            }
        }
        .confirmationDialog(
            "aplicar \(item.exposure?.discountLabel ?? "desconto") e megafonar?",
            isPresented: $isConfirmingApply,
            titleVisibility: .visible
        ) {
            Button("aplicar desconto") { runner.applyDiscount(for: item.id) }
            Button("cancelar", role: .cancel) {}
        } message: {
            if let current = item.product.formattedPrice, let suggested = suggestedPriceText {
                Text("o preço vai de \(current) para \(suggested), e o produto é megafonado na hora.")
            }
        }
        .confirmationDialog(
            "repostar este produto?",
            isPresented: $isConfirmingRepost,
            titleVisibility: .visible
        ) {
            Button("repostar") {
                accountsStore.postQueue.enqueue(product: item.product, source: account, destination: account)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("entra na fila de ações, reaproveitando título, descrição, preço e fotos — acompanhe o andamento por lá.")
        }
        .confirmationDialog(
            "apagar este produto?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("apagar", role: .destructive) {
                accountsStore.postQueue.enqueueDelete(product: item.product, account: account)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("ação irreversível: entra na fila de ações e o anúncio é apagado do enjoei de vez, sem chance de recuperar.")
        }
        .confirmationDialog(
            "inativar este produto?",
            isPresented: $isConfirmingInactivate,
            titleVisibility: .visible
        ) {
            Button("inativar") {
                accountsStore.postQueue.enqueueInactivate(product: item.product, account: account)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("entra na fila de ações e sai da vitrine de publicados — dá pra reativar depois direto no enjoei.")
        }
        .sheet(isPresented: $isShowingErrorDetail) {
            if let message = item.status.failureMessage {
                MegaphoneErrorDetailSheet(product: item.product, message: message, detail: runner.failureDetails[item.id])
            }
        }
        .opacity(isGone ? 0.4 : 1)
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
    }

    /// O que vai embaixo do título — a situação do produto tem prioridade sobre o preço: apagado,
    /// inativado e falha falam mais alto que o preço de sempre.
    @ViewBuilder
    private var detailLine: some View {
        if isDeleted {
            Text("produto apagado")
                .font(.subheadline)
                .foregroundStyle(.statusFailure)
        } else if isInactivated {
            Text("produto inativado")
                .font(.subheadline)
                .foregroundStyle(.supportingText)
        } else if let message = item.status.failureMessage {
            Button {
                isShowingErrorDetail = true
            } label: {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.statusFailure)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        } else {
            priceLine
        }
    }

    /// Preço atual sempre no texto padrão, em semibold — o original riscado (quando a loja já
    /// mostra com desconto) e o preço sugerido pelo megafone ficam no texto de apoio, e logo depois
    /// do atual o quanto de desconto o anúncio já tem ("-14%"), em amarelo como antes do redesign —
    /// o número que diz o quanto o produto já baixou, ao lado do selo com o desconto novo sugerido.
    /// Verde saiu do preço de propósito: agora só significa status.
    ///
    /// Um `Text` só, emendado, em vez de uma `HStack` — com o botão de desconto ao lado e o tamanho
    /// de texto do app (`.xxxLarge`), não cabe numa linha; assim quebra pra segunda em vez de
    /// cortar os preços no meio.
    private var priceLine: some View {
        var segments: [Text] = []
        if let original = item.product.formattedOriginalPrice, item.appliedDiscountPercent != nil {
            segments.append(Text(original).strikethrough().foregroundStyle(.supportingText))
        }
        if let current = item.product.formattedPrice {
            segments.append(Text(current).fontWeight(.semibold))
        }
        if let applied = item.appliedDiscountPercent {
            segments.append(Text("-\(applied)%").fontWeight(.semibold).foregroundStyle(.statusDecision))
        }
        if isAwaitingDiscount, let suggested = suggestedPriceText {
            segments.append(
                Text(isCompact ? "→ \(suggested)" : "→ \(suggested) com o desconto").foregroundStyle(.supportingText)
            )
        }
        if isInFlight {
            segments.append(Text("megafonando agora…").foregroundStyle(.statusInProgress))
        }
        let line = segments.dropFirst().reduce(segments.first ?? Text(verbatim: "")) { Text("\($0) \($1)") }
        // Até 3 linhas: original, atual, desconto já aplicado e o sugerido não cabem em 2 no tamanho
        // de letra do app ao lado do selo de desconto — melhor crescer a row que cortar um preço.
        return line
            .productPriceFont()
            .lineLimit(3)
    }

    private var suggestedPriceText: String? {
        guard let price = item.exposure?.priceToIncreaseExposure else { return nil }
        return price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    /// O percentual sugerido de quem está em "pedem desconto" — sempre à mostra, mesmo selecionando
    /// ou depois da rodada já ter megafonado o produto (sem o desconto): é ele que diz o quanto
    /// cada um pede, inclusive pra escolher quais aplicar em massa.
    private var discountPercentText: String? {
        guard !isGone, item.needsDiscountDecision else { return nil }
        return item.exposure?.discountLabel ?? item.computedDiscountPercent.map { "- \($0)%" }
    }

    @ViewBuilder
    private var trailingView: some View {
        if isSelecting {
            // A row inteira marca/desmarca — o percentual fica só como informação.
            if let discountPercentText {
                discountBadge(discountPercentText)
            }
        } else if isAwaitingDiscount {
            discountButton
            if !isCompact { moreMenu }
        } else if isGone {
            goneIcon
            if !isCompact { moreMenu }
        } else if isCompact {
            if let discountPercentText {
                discountBadge(discountPercentText)
            }
            // Só uma coisa na ponta: parado e ainda sem status, o "..."; com rodada em aberto ou
            // já com resultado, o status (as ações seguem no menu de contexto).
            if item.status == .pending, !isRoundActive {
                moreMenu
            } else {
                statusIcon
            }
        } else {
            if let discountPercentText {
                discountBadge(discountPercentText)
            }
            statusIcon
            moreMenu
        }
    }

    /// Mesmo formato do botão de aplicar, mas só informativo — fundo claro em vez de preenchido,
    /// pra não parecer um botão onde tocar não aplica nada.
    private func discountBadge(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.statusDecision)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.statusDecision.opacity(0.15), in: .capsule)
            .fixedSize()
            .accessibilityLabel("desconto sugerido de \(text)")
    }

    private var discountButton: some View {
        Button {
            isConfirmingApply = true
        } label: {
            HStack(spacing: 4) {
                if !isCompact {
                    Image(systemName: "tag")
                }
                Text(item.exposure?.discountLabel ?? "aplicar")
            }
            .font(.subheadline.weight(.bold))
        }
        .buttonStyle(.tinted(.statusDecision, size: 34))
        .accessibilityLabel("aplicar desconto de \(item.exposure?.discountLabel ?? "")")
    }

    @ViewBuilder
    private var goneIcon: some View {
        if isDeleted {
            Image(systemName: "trash.fill")
                .foregroundStyle(.statusFailure)
                .accessibilityLabel("apagado")
        } else {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.supportingText)
                .accessibilityLabel("inativado")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .font(.title3)
                .foregroundStyle(.supportingText)
                .accessibilityLabel("na fila")
        case .megaphoning where isInFlight:
            ProgressView()
                .tint(.statusInProgress)
                .accessibilityLabel("em andamento")
        case .megaphoning:
            // No pedaço em voo, mas ainda não chegou a vez dele.
            Image(systemName: "clock")
                .font(.title3)
                .foregroundStyle(.supportingText)
                .accessibilityLabel("na fila")
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.statusSuccess)
                .accessibilityLabel("megafonado")
        case .failed:
            Button {
                isShowingErrorDetail = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.statusFailure)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("falhou, ver detalhe do erro")
        }
    }

    private var moreMenu: some View {
        Menu {
            actionsMenuContent
        } label: {
            // O menu fecha assim que o usuário confirma — sem isso, o "repostando…"/"apagando…"/
            // "inativando…" lá dentro some da vista e a row fica sem nenhum sinal de que a
            // operação ainda está rolando.
            if isActionInFlight {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.supportingText)
            }
        }
        .accessibilityLabel("mais ações")
    }

    @ViewBuilder
    private var actionsMenuContent: some View {
        ShareLink(item: item.product.storePageURL) {
            Label("compartilhar", systemImage: "square.and.arrow.up")
        }
        if !isGone {
            if let whatsAppShareURL {
                Link(destination: whatsAppShareURL) {
                    Label("compartilhar no whatsapp", systemImage: "message")
                }
            }
            Button {
                isConfirmingRepost = true
            } label: {
                if repostStatus == .megaphoning {
                    Label("repostando…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("repostar produto", systemImage: "doc.on.doc")
                }
            }
            .disabled(repostStatus == .megaphoning)

            Button {
                isConfirmingInactivate = true
            } label: {
                if inactivateStatus == .megaphoning {
                    Label("inativando…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("inativar produto", systemImage: "archivebox")
                }
            }
            .disabled(inactivateStatus == .megaphoning)

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                if deleteStatus == .megaphoning {
                    Label("apagando…", systemImage: "trash")
                } else {
                    Label("apagar produto", systemImage: "trash")
                }
            }
            .disabled(deleteStatus == .megaphoning)
        }
    }

    /// Abre o WhatsApp direto na tela de encaminhar, já com o link preenchido. Sem checar se o
    /// WhatsApp está instalado — sem isso registrado no Info.plist, `canOpenURL` sempre devolve
    /// falso; sem o app instalado, o toque simplesmente não faz nada.
    private var whatsAppShareURL: URL? {
        let text = "\(item.product.title)\n\(item.product.storePageURL.absoluteString)"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "whatsapp://send?text=\(encoded)")
    }
}

#Preview {
    let product = EnjoeiProduct(
        id: 145657034,
        title: "brinco argola estrela 50mm leve moderno joia prata 925",
        path: "brinco-argola-estrela-145657034",
        photoPublicID: nil,
        currentPrice: 273,
        originalPrice: 399
    )
    let discountedProduct = EnjoeiProduct(
        id: 142963399,
        title: "colar coração prata 925",
        path: "colar-coracao-142963399",
        photoPublicID: nil,
        currentPrice: 799,
        originalPrice: 799
    )
    let exposure = MegaphoneExposure(
        productID: 142963399,
        kind: .maximumAfterDiscount,
        priceToIncreaseExposure: 351,
        discountLabel: "- 56%"
    )
    let webSession = EnjoeiWebSession(dataStoreIdentifier: UUID())
    let runner = MegaphoneRunner(client: WebViewEnjoeiClient(webSession: webSession))
    let account = AccountSession(
        id: UUID(),
        user: EnjoeiUser(id: 1, nickname: "antonia", name: "antonia", avatarPublicID: nil, availableProductsCount: nil),
        dependencies: AccountDependencies(
            client: WebViewEnjoeiClient(webSession: webSession),
            sessionClearer: webSession,
            webView: nil
        )
    )
    return ScrollView {
        VStack(spacing: 0) {
            MegaphoneRowView(
                item: MegaphoneItem(product: discountedProduct, status: .pending, exposure: exposure),
                runner: runner,
                account: account
            )
            MegaphoneRowView(item: MegaphoneItem(product: product, status: .pending), runner: runner, account: account)
            MegaphoneRowView(
                item: MegaphoneItem(product: product, status: .pending),
                runner: runner,
                account: account,
                isRoundActive: true
            )
            MegaphoneRowView(
                item: MegaphoneItem(product: product, status: .megaphoning),
                runner: runner,
                account: account,
                isRoundActive: true,
                isActive: true
            )
            MegaphoneRowView(item: MegaphoneItem(product: product, status: .succeeded), runner: runner, account: account)
            MegaphoneRowView(
                item: MegaphoneItem(product: product, status: .failed("o enjoei respondeu com erro 504.")),
                runner: runner,
                account: account
            )
            MegaphoneRowView(
                item: MegaphoneItem(product: product, status: .pending),
                runner: runner,
                account: account,
                isSelecting: true,
                isSelected: true
            )
        }
    }
    .environment(AccountsStore())
}
