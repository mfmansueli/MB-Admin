import SwiftUI

/// Linha da lista de megafone: foto, título, preço (com o desconto já aplicado na loja, quando
/// houver) e o que aconteceu com aquele produto — inclui o botão de aplicar o desconto sugerido
/// pelo megafone, quando o produto pede essa decisão.
struct MegaphoneRowView: View {
    let item: MegaphoneItem
    let runner: MegaphoneRunner

    @State private var isConfirmingApply = false
    @State private var isConfirmingRepost = false
    @State private var isShowingRepostStatus = false
    @State private var isConfirmingDelete = false
    @State private var isShowingDeleteStatus = false

    private var repostStatus: MegaphoneStatus { runner.repostStatuses[item.id] ?? .pending }
    private var deleteStatus: MegaphoneStatus { runner.deleteStatuses[item.id] ?? .pending }
    private var isDeleted: Bool { deleteStatus == .succeeded }

    var body: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: item.product)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.product.title)
                    .font(.headline)
                    .lineLimit(2)
                if isDeleted {
                    Text("produto apagado")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } else if let message = item.status.failureMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                } else {
                    priceLine
                }
            }

            Spacer(minLength: 8)

            trailingView

            moreMenu
        }
        .padding(.vertical, 2)
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
                isShowingRepostStatus = true
                runner.repost(productID: item.id)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("cria um anúncio novo idêntico a este, reaproveitando título, descrição, preço e fotos.")
        }
        .sheet(isPresented: $isShowingRepostStatus) {
            RepostStatusSheet(
                status: repostStatus,
                productURL: runner.repostedProductURLs[item.id],
                onDismiss: { isShowingRepostStatus = false }
            )
        }
        .confirmationDialog(
            "apagar este produto?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("apagar", role: .destructive) {
                isShowingDeleteStatus = true
                runner.deleteProduct(productID: item.id)
            }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("ação irreversível: o anúncio é apagado do enjoei de vez, sem chance de recuperar.")
        }
        .sheet(isPresented: $isShowingDeleteStatus) {
            DeleteStatusSheet(status: deleteStatus, onDismiss: { isShowingDeleteStatus = false })
        }
        .opacity(isDeleted ? 0.4 : 1)
    }

    /// Preço já riscado quando a loja mostra o produto com desconto — independente de qualquer
    /// coisa relacionada ao megafone.
    @ViewBuilder
    private var priceLine: some View {
        HStack(spacing: 6) {
            if let original = item.product.formattedOriginalPrice, item.product.originalPrice != item.product.currentPrice {
                Text(original)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            if let current = item.product.formattedPrice {
                Text(current)
                    .font(.subheadline.weight(.semibold))
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
            if isDeleted {
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
            // O menu fecha assim que o usuário confirma — sem isso, o "repostando…"/"apagando…" lá
            // dentro some da vista e a row fica sem nenhum sinal de que a operação ainda está rolando.
            if repostStatus == .megaphoning || deleteStatus == .megaphoning {
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
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
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
    let runner = MegaphoneRunner(
        client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID()))
    )
    return List {
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .pending), runner: runner)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .megaphoning), runner: runner)
        MegaphoneRowView(item: MegaphoneItem(product: product, status: .succeeded), runner: runner)
        MegaphoneRowView(
            item: MegaphoneItem(product: product, status: .failed("limite diário atingido")),
            runner: runner
        )
        MegaphoneRowView(
            item: MegaphoneItem(product: discountedProduct, status: .pending, exposure: exposure),
            runner: runner
        )
    }
}
