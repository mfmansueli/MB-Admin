import SwiftUI

/// Uma linha da lista de inativos: foto, título, preço e desde quando está inativo — em modo de
/// seleção, vira uma linha marcável.
struct InactiveProductRowView: View {
    let product: InactiveProduct
    let account: AccountSession
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    @State private var isConfirmingActivate = false
    @State private var isConfirmingRepost = false
    @Environment(AccountsStore.self) private var accountsStore

    private var activateStatus: MegaphoneStatus { account.runner.activateStatuses[product.id] ?? .pending }
    private var isActivated: Bool { activateStatus == .succeeded }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            ProductPhotoView(product: product)

            VStack(alignment: .leading, spacing: 2) {
                // Mesmo tamanho de fonte da row de "publicados" (`MegaphoneRowView`).
                Text(product.title)
                    .productTitleFont()
                    .lineLimit(2)
                if isActivated {
                    Text("produto ativado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if let price = product.formattedPrice {
                        Text(price)
                            .productPriceFont()
                            .foregroundStyle(.secondary)
                    }
                    if let inactiveSince = product.inactiveSince {
                        Text("inativo desde \(inactiveSince)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Sempre presente, mesmo selecionando (sem o menu à direita) — sem isso, a `HStack`
            // encolhe pro tamanho do conteúdo em vez de ocupar a largura da row, e o divisor da
            // lista (que segue essa largura) fica curto em vez de ir de ponta a ponta.
            Spacer(minLength: 8)

            if !isSelecting {
                moreMenu
            }
        }
        .padding(.vertical, 2)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima da foto — ver o mesmo comentário em `MegaphoneRowView`.
        .background(.background)
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
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
        .opacity(isActivated ? 0.4 : 1)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
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
        } label: {
            if activateStatus == .megaphoning {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A fila só usa `id` (pra ler o template de novo), `title` e `photoPublicID` (pra exibir) — o
    /// resto do `EnjoeiProduct` não importa aqui, então fica com valores neutros. Mesma ideia do
    /// repost em massa (`InactiveProductsListView.repostarSelecionados`).
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
