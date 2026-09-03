import SwiftUI

/// Uma linha nas seções "só nessa conta" — produto sem par na outra. Deixa compartilhar o link, ou
/// postar o mesmo produto direto na conta que ainda não tem ele — em modo de seleção, vira uma
/// linha marcável pra entrar na fila de ações junto com outras.
struct UnmatchedProductRowView: View {
    let product: EnjoeiProduct
    let sourceAccount: AccountSession
    let destinationAccount: AccountSession
    let poster: CrossAccountPoster
    let postQueue: PostQueue
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    @State private var isConfirmingPost = false
    @State private var isShowingPostStatus = false

    private var postTarget: PostTarget { PostTarget(productID: product.id, destinationAccountID: destinationAccount.id) }
    private var postStatus: MegaphoneStatus { poster.statuses[postTarget] ?? .pending }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
            }
            // Mesmo tamanho de foto de "publicados" e "inativos" — todas as listas de produto
            // usam o padrão de 64pt do `ProductPhotoView`.
            ProductPhotoView(product: product)
            VStack(alignment: .leading, spacing: 2) {
                // Mesmo tamanho de fonte da row de "publicados" (`MegaphoneRowView`).
                Text(product.title)
                    .productTitleFont()
                    .lineLimit(2)
                if let price = product.formattedPrice {
                    Text(price)
                        .productPriceFont()
                        .foregroundStyle(.secondary)
                }
            }
            // Sempre presente, mesmo selecionando (sem os botões à direita) — sem isso, a `HStack`
            // encolhe pro tamanho do conteúdo em vez de ocupar a largura da row, e o divisor da
            // lista (que segue essa largura) fica curto em vez de ir de ponta a ponta.
            Spacer(minLength: 8)
            if !isSelecting {
                ShareLink(item: product.storePageURL) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                postButton
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
        }
        .confirmationDialog(
            "postar este produto em \(destinationAccount.user.name)?",
            isPresented: $isConfirmingPost,
            titleVisibility: .visible
        ) {
            Button("postar em \(destinationAccount.user.name)") {
                isShowingPostStatus = true
                postQueue.postSingle(product: product, from: sourceAccount, to: destinationAccount)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("cria um anúncio novo em \(destinationAccount.user.name) com título, descrição, preço e fotos desse produto.")
        }
        .sheet(isPresented: $isShowingPostStatus) {
            RepostStatusSheet(
                status: postStatus,
                productURL: poster.postedProductURLs[postTarget],
                onDismiss: { isShowingPostStatus = false }
            )
        }
    }

    @ViewBuilder
    private var postButton: some View {
        // O bloqueio de 2 minutos passa sozinho sem nenhuma outra mudança de estado disparar uma
        // atualização da view — sem o tick daqui, o botão continuaria desabilitado depois do
        // cooldown acabar, até algo mais forçar um redraw.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Button {
                isConfirmingPost = true
            } label: {
                switch postStatus {
                case .megaphoning:
                    HStack {
                        ProgressView()
                        Text("postando em \(destinationAccount.user.name)…")
                    }
                case .succeeded:
                    Label("postado em \(destinationAccount.user.name)", systemImage: "checkmark.circle.fill")
                case .failed:
                    Label("postar em \(destinationAccount.user.name)", systemImage: "paperplane.fill")
                case .pending:
                    Label("postar em \(destinationAccount.user.name)", systemImage: "paperplane.fill")
                }
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(postButtonTint)
            .disabled(postStatus == .megaphoning || postStatus == .succeeded || poster.isInCooldown)
        }
    }

    private var postButtonTint: Color {
        if postStatus.failureMessage != nil { return .red }
        return .green
    }
}

#Preview {
    let accountA = AccountSession(
        id: UUID(),
        user: EnjoeiUser(id: 1, nickname: "loja-a", name: "loja A", avatarPublicID: nil, availableProductsCount: nil),
        dependencies: AccountDependencies(
            client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID())),
            sessionClearer: EnjoeiWebSession(dataStoreIdentifier: UUID()),
            webView: nil
        )
    )
    let accountB = AccountSession(
        id: UUID(),
        user: EnjoeiUser(id: 2, nickname: "loja-b", name: "loja B", avatarPublicID: nil, availableProductsCount: nil),
        dependencies: AccountDependencies(
            client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID())),
            sessionClearer: EnjoeiWebSession(dataStoreIdentifier: UUID()),
            webView: nil
        )
    )
    let poster = CrossAccountPoster()
    return UnmatchedProductRowView(
        product: EnjoeiProduct(
            id: 145657034,
            title: "brinco argola estrela 50mm",
            path: "brinco-argola-estrela-145657034",
            photoPublicID: nil,
            currentPrice: 273,
            originalPrice: 399
        ),
        sourceAccount: accountA,
        destinationAccount: accountB,
        poster: poster,
        postQueue: PostQueue(poster: poster, accountsProvider: { [accountA, accountB] in [accountA, accountB] })
    )
    .padding()
}
