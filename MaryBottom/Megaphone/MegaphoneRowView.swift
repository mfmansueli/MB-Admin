import SwiftUI

/// Linha da lista de megafone: foto, título, preço (com o desconto já aplicado na loja, quando
/// houver) e o que aconteceu com aquele produto — inclui o botão de aplicar o desconto sugerido
/// pelo megafone, quando o produto pede essa decisão.
struct MegaphoneRowView: View {
    let item: MegaphoneItem
    let runner: MegaphoneRunner
    let account: AccountSession
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

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

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }

            ProductPhotoView(product: item.product)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .productTitleFont()
                    .lineLimit(2)
                if isDeleted {
                    Text("produto apagado")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else if isInactivated {
                    Text("produto inativado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let message = item.status.failureMessage {
                    Button {
                        isShowingErrorDetail = true
                    } label: {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    priceLine
                }
            }

            Spacer(minLength: 8)

            if !isSelecting {
                trailingView

                moreMenu
            }
        }
        .padding(.vertical, 2)
        // Fundo sólido (mesmo que igual ao da página) — sem isso, no Mac Catalyst o scroll do
        // mouse/trackpad só funciona em cima de conteúdo com pixel de verdade (a foto), porque a
        // `ScrollView`/`LazyVStack` (ver quem usa esta row) não tem `List` por baixo roteando o
        // gesto sozinha. `.contentShape` não resolve isso — é pra gesture recognizers de toque, o
        // scroll do mouse no Catalyst passa por outro caminho que precisa de uma camada desenhada.
        .background(.background)
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
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
        .opacity(isDeleted || isInactivated ? 0.4 : 1)
    }

    /// Preço já riscado quando a loja mostra o produto com desconto — independente de qualquer
    /// coisa relacionada ao megafone.
    @ViewBuilder
    private var priceLine: some View {
        HStack(spacing: 6) {
            if let original = item.product.formattedOriginalPrice, item.product.originalPrice != item.product.currentPrice {
                Text(original)
                    .productPriceFont()
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            if let current = item.product.formattedPrice {
                Text(current)
                    .productPriceFont(weight: .semibold)
                    .foregroundStyle(.green)
            }
            if let percent = item.computedDiscountPercent {
                Text("-\(percent)%")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var suggestedPriceText: String? {
        guard let price = item.exposure?.priceToIncreaseExposure else { return nil }
        return price.formatted(.currency(code: "BRL").presentation(.narrow))
    }

    @ViewBuilder
    private var trailingView: some View {
        if isDeleted {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
        } else if isInactivated {
            Image(systemName: "archivebox.fill")
                .foregroundStyle(.secondary)
        } else if item.status == .pending, let exposure = item.exposure, exposure.kind.requiresDiscountDecision {
            Button {
                isConfirmingApply = true
            } label: {
                Text(exposure.discountLabel ?? "aplicar")
                    .font(.subheadline.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        } else {
            statusIcon
        }
    }

    private var moreMenu: some View {
        Menu {
            if isDeleted || isInactivated {
                ShareLink(item: item.product.storePageURL) {
                    Label("compartilhar", systemImage: "square.and.arrow.up")
                }
            } else {
                ShareLink(item: item.product.storePageURL) {
                    Label("compartilhar", systemImage: "square.and.arrow.up")
                }
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
        } label: {
            // O menu fecha assim que o usuário confirma — sem isso, o "repostando…"/"apagando…"/
            // "inativando…" lá dentro some da vista e a row fica sem nenhum sinal de que a
            // operação ainda está rolando.
            if repostStatus == .megaphoning || deleteStatus == .megaphoning || inactivateStatus == .megaphoning {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
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

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
        case .megaphoning:
            ProgressView()
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Button {
                isShowingErrorDetail = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
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
    return List {
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .pending), runner: runner, account: account)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .megaphoning), runner: runner, account: account)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .succeeded), runner: runner, account: account)
        MegaphoneRowView(
            item: MegaphoneItem(product: product, status: .failed("limite diário atingido")),
            runner: runner,
            account: account
        )
        MegaphoneRowView(
            item: MegaphoneItem(product: discountedProduct, status: .pending, exposure: exposure),
            runner: runner,
            account: account
        )
    }
    .environment(AccountsStore())
}
