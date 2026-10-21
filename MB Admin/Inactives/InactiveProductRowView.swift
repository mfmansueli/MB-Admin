import SwiftUI

/// Uma linha da lista de inativos: foto, título, preço e desde quando está inativo — em modo de
/// seleção, vira uma linha marcável. As ações do "..." ficam também no menu de contexto (toque
/// longo / clique direito), como na aba de publicados.
struct InactiveProductRowView: View {
    let product: InactiveProduct
    let account: AccountSession
    var isSelecting = false
    var isSelected = false
    var isCompact = true
    var onToggleSelection: () -> Void = {}

    @State private var isConfirmingActivate = false
    @State private var isConfirmingRepost = false
    @State private var isConfirmingDelete = false
    @Environment(AccountsStore.self) private var accountsStore

    private var activateStatus: MegaphoneStatus { account.runner.activateStatuses[product.id] ?? .pending }
    private var isActivated: Bool { activateStatus == .succeeded }
    /// Mesma fonte da aba de publicados (`MegaphoneRowView`): apagar passa pela fila, que delega
    /// pro `MegaphoneRunner` da conta — o status mora lá, chaveado só pelo id do produto.
    private var deleteStatus: MegaphoneStatus { account.runner.deleteStatuses[product.id] ?? .pending }
    private var isDeleted: Bool { deleteStatus == .succeeded }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                selectionIndicator
            }
            ProductPhotoView(product: product)

            VStack(alignment: .leading, spacing: 2) {
                // Mesmo tamanho de fonte da row de "publicados" (`MegaphoneRowView`).
                Text(product.title)
                    .productTitleFont()
                    .lineLimit(2)
                if isDeleted {
                    Text("produto apagado")
                        .font(.subheadline)
                        .foregroundStyle(.statusFailure)
                } else if isActivated {
                    Text("produto ativado")
                        .font(.subheadline)
                        .foregroundStyle(.statusSuccess)
                } else {
                    if let price = product.formattedPrice {
                        Text(price)
                            .productPriceFont()
                            .fontWeight(.semibold)
                    }
                    if let inactiveSince = product.inactiveSince {
                        Text("inativo desde \(inactiveSince)")
                            .font(.caption)
                            .foregroundStyle(.supportingText)
                    }
                }
            }

            // Sempre presente, mesmo selecionando (sem o menu à direita) — sem isso, a `HStack`
            // encolhe pro tamanho do conteúdo em vez de ocupar a largura da row, e o divisor da
            // lista (que segue essa largura) fica curto em vez de ir de ponta a ponta.
            Spacer(minLength: 8)

            if isDeleted {
                // Nada mais a fazer com um produto que não existe mais no enjoei — no lugar do
                // menu, o mesmo ícone que a aba de publicados mostra pra um produto apagado.
                Image(systemName: "trash.fill")
                    .foregroundStyle(.statusFailure)
            } else if !isSelecting {
                moreMenu
            }
        }
        .padding(.horizontal, isCompact ? 16 : 24)
        .padding(.vertical, 8)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima da foto — ver o mesmo comentário em `MegaphoneRowView`.
        .background(.background)
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
        }
        .contextMenu {
            if !isSelecting, !isDeleted {
                menuContent
            }
        }
        .confirmationDialog(
            "ativar este produto de novo?",
            isPresented: $isConfirmingActivate,
            titleVisibility: .visible
        ) {
            Button("ativar") {
                accountsStore.postQueue.enqueueActivate(product: placeholderProduct, account: account)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("entra na fila de ações e volta pra vitrine de publicados.")
        }
        .confirmationDialog(
            "repostar este produto?",
            isPresented: $isConfirmingRepost,
            titleVisibility: .visible
        ) {
            Button("repostar") {
                accountsStore.postQueue.enqueue(product: placeholderProduct, source: account, destination: account)
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
                accountsStore.postQueue.enqueueDelete(product: placeholderProduct, account: account)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("ação irreversível: entra na fila de ações e o anúncio é apagado do enjoei de vez, sem chance de recuperar.")
        }
        .opacity(isActivated || isDeleted ? 0.4 : 1)
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

    private var moreMenu: some View {
        Menu {
            menuContent
        } label: {
            if activateStatus == .megaphoning || deleteStatus == .megaphoning {
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
    private var menuContent: some View {
        ShareLink(item: product.storePageURL) {
            Label("compartilhar", systemImage: "square.and.arrow.up")
        }
        if !isActivated, let whatsAppShareURL {
            Link(destination: whatsAppShareURL) {
                Label("compartilhar no whatsapp", systemImage: "message")
            }
        }
        Button {
            isConfirmingRepost = true
        } label: {
            Label("repostar", systemImage: "doc.on.doc.fill")
        }
        if !isActivated {
            Button {
                isConfirmingActivate = true
            } label: {
                if activateStatus == .megaphoning {
                    Label("ativando…", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("ativar produto", systemImage: "tray.and.arrow.up.fill")
                }
            }
            .disabled(activateStatus == .megaphoning)
        }
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

    /// A fila só usa `id` (pra ler o template de novo), `title` e `photoPublicID` (pra exibir) — o
    /// resto do `EnjoeiProduct` não importa aqui, então fica com valores neutros. Mesma ideia do
    /// repost em massa (`InactiveProductsListView.perform(_:)`).
    private var placeholderProduct: EnjoeiProduct {
        EnjoeiProduct(
            id: product.id,
            title: product.title,
            path: product.path,
            photoPublicID: product.photoPublicID,
            currentPrice: product.price,
            originalPrice: product.price
        )
    }

    /// Abre o WhatsApp direto na tela de encaminhar, já com o link preenchido. Sem checar se o
    /// WhatsApp está instalado — sem isso registrado no Info.plist, `canOpenURL` sempre devolve
    /// falso; sem o app instalado, o toque simplesmente não faz nada.
    private var whatsAppShareURL: URL? {
        let text = "\(product.title)\n\(product.storePageURL.absoluteString)"
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "whatsapp://send?text=\(encoded)")
    }
}

#Preview {
    let webSession = EnjoeiWebSession(dataStoreIdentifier: UUID())
    let account = AccountSession(
        id: UUID(),
        user: EnjoeiUser(id: 1, nickname: "antonia", name: "antonia", avatarPublicID: nil, availableProductsCount: nil),
        dependencies: AccountDependencies(
            client: WebViewEnjoeiClient(webSession: webSession),
            sessionClearer: webSession,
            webView: nil
        )
    )
    return InactiveProductRowView(
        product: InactiveProduct(
            id: 143304960,
            path: "brinco-pino-diamond-cravejado-10mm-prata-295-143304960",
            title: "brinco pino diamond cravejado 10mm prata 295",
            price: 229,
            photoPublicID: nil,
            inactiveSince: "12/03/2026"
        ),
        account: account
    )
    .padding()
    .environment(AccountsStore())
}
