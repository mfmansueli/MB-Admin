import SwiftUI

/// Uma linha nas seções "só em loja A" — produto sem par na outra conta: foto, título, preço e, logo
/// embaixo, o botão de postar o mesmo produto direto na conta que ainda não tem ele. Em modo de
/// seleção, vira uma linha marcável pra entrar na fila de ações junto com outras. Compartilhar o
/// link fica no menu de contexto.
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
        HStack(alignment: .top, spacing: 12) {
            if isSelecting {
                selectionIndicator
                    .frame(maxHeight: .infinity)
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
                        .foregroundStyle(.supportingText)
                }
                if !isSelecting {
                    postButton
                        .padding(.top, 4)
                }
            }
            // Sempre presente — sem isso, a `HStack` encolhe pro tamanho do conteúdo em vez de
            // ocupar a largura da row, e o fundo do cartão fica com um buraco à direita.
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Fundo sólido pro scroll do mouse/trackpad funcionar em qualquer área da row no Mac
        // Catalyst, não só em cima da foto — ver o mesmo comentário em `MegaphoneRowView`.
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .contentShape(.rect)
        .onTapGesture {
            if isSelecting { onToggleSelection() }
        }
        .contextMenu {
            if !isSelecting {
                ShareLink(item: product.storePageURL) {
                    Label("compartilhar", systemImage: "square.and.arrow.up")
                }
            }
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

    /// Cápsula cinza com o destino no nome ("postar em loja B") — vira "postando…", "postado" (verde)
    /// ou o mesmo convite em vermelho depois de uma falha.
    /// `poster.isInCooldown` zera sozinho quando o bloqueio expira (ver
    /// `CrossAccountPoster.scheduleCooldownExpiry`) — não precisa de um tick próprio aqui.
    private var postButton: some View {
        Button {
            isConfirmingPost = true
        } label: {
            HStack(spacing: 6) {
                switch postStatus {
                case .megaphoning:
                    ProgressView()
                        .controlSize(.small)
                    Text("postando em \(destinationAccount.user.name)…")
                case .succeeded:
                    Image(systemName: "checkmark.circle.fill")
                    Text("postado em \(destinationAccount.user.name)")
                case .failed, .pending:
                    Image(systemName: "paperplane")
                    Text("postar em \(destinationAccount.user.name)")
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(postButtonStyle)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Color(uiColor: .tertiarySystemFill), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(postStatus == .megaphoning || postStatus == .succeeded || poster.isInCooldown)
        .opacity(poster.isInCooldown && postStatus == .pending ? 0.4 : 1)
    }

    private var postButtonStyle: AnyShapeStyle {
        switch postStatus {
        case .succeeded: AnyShapeStyle(Color.statusSuccess)
        case .failed: AnyShapeStyle(Color.statusFailure)
        case .pending, .megaphoning: AnyShapeStyle(.primary)
        }
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
