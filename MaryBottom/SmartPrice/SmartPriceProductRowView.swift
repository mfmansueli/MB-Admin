import SwiftUI

/// Uma linha da lista de "sem preço esperto": foto, preço, o rótulo colorido que o Enjoei já
/// calcula pra cada anúncio (`SmartPriceProduct.statusText`/`statusColor`) e a faixa em que o
/// preço esperto poderia variar — em modo de seleção, vira uma linha marcável (exceto quando
/// `blocked`, que não aceita a ação de ativar).
struct SmartPriceProductRowView: View {
    let item: SmartPriceListItem
    let loader: SmartPriceProductsLoader
    var isSelecting = false
    var isSelected = false
    var onToggleSelection: () -> Void = {}

    @State private var isConfirmingActivate = false

    /// Reaproveita `MegaphoneStatus`: `.megaphoning` aqui significa "ativando", mesmo raciocínio de
    /// `MegaphoneRunner.activateStatuses`/`inactivateStatuses`.
    private var activationStatus: MegaphoneStatus { loader.activationStatuses[item.id] ?? .pending }
    private var isActivated: Bool { activationStatus == .succeeded }
    private var isActivating: Bool { activationStatus == .megaphoning }
    private var isBlocked: Bool { item.product.blocked }

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isBlocked ? Color.secondary.opacity(0.4) : (isSelected ? Color.accentColor : Color.secondary))
                    .font(.title3)
            }
            ProductPhotoView(photoURL: item.photoURL, largePhotoURL: item.largePhotoURL, title: item.title)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .productTitleFont()
                    .lineLimit(2)
                if isActivated {
                    Text("preço esperto ativado")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.product.formattedPrice)
                        .productPriceFont()
                        .foregroundStyle(.secondary)
                    if let statusText = item.product.statusText {
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(Color(hex: item.product.statusColor) ?? .secondary)
                    }
                    if isBlocked {
                        Text("bloqueado para essa ação")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                // Faixa em que o preço esperto pode variar — mostrada mesmo já ativado, já que é
                // o limite que o Enjoei vai respeitar dali pra frente, não só uma prévia de antes
                // de ativar (essa também aparece na confirmação de ativar, mais abaixo).
                Text("varia de \(item.product.formattedMinPrice) a \(item.product.formattedMaxPrice)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            if isSelecting, !isBlocked { onToggleSelection() }
        }
        .confirmationDialog(
            "ativar o preço esperto deste produto?",
            isPresented: $isConfirmingActivate,
            titleVisibility: .visible
        ) {
            Button("ativar") { loader.activate(productIDs: [item.id]) }
            Button("cancelar", role: .cancel) {}
        } message: {
            Text("o enjoei passa a ajustar o preço sozinho entre \(item.product.formattedMinPrice) e \(item.product.formattedMaxPrice).")
        }
        .opacity(isActivated ? 0.4 : 1)
    }

    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            if let storePageURL = item.storePageURL {
                ShareLink(item: storePageURL) {
                    Label("compartilhar", systemImage: "square.and.arrow.up")
                }
            }
            if !isActivated, !isBlocked {
                Button {
                    isConfirmingActivate = true
                } label: {
                    if isActivating {
                        Label("ativando…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("ativar preço esperto", systemImage: "sparkles")
                    }
                }
                .disabled(isActivating)
            }
        } label: {
            if isActivating {
                ProgressView()
            } else {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SmartPriceProductRowView(
        item: SmartPriceListItem(
            product: SmartPriceProduct(
                id: 150087687,
                price: 589,
                minPrice: 412,
                maxPrice: 706,
                blocked: false,
                smartPriceEnabled: false,
                statusText: "preço alto, venda lenta",
                statusColor: "#FF4D00",
                photoPublicID: nil
            ),
            matched: EnjoeiProduct(
                id: 150087687,
                title: "brinco argola estrela 50mm",
                path: "brinco-argola-estrela-150087687",
                photoPublicID: nil,
                currentPrice: 589,
                originalPrice: 589
            )
        ),
        loader: SmartPriceProductsLoader(
            client: WebViewEnjoeiClient(webSession: EnjoeiWebSession(dataStoreIdentifier: UUID()))
        )
    )
    .padding()
}
