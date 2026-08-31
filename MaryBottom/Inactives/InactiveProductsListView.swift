import SwiftUI

/// Conteúdo da aba "inativos" da tela de detalhe da conta: lista os produtos inativos da própria
/// loja e deixa selecionar vários pra republicar de uma vez, entrando na mesma fila de publicação
/// usada pela comparação entre contas — aqui origem e destino são sempre a própria conta.
struct InactiveProductsListView: View {
    let account: AccountSession

    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int> = []
    @Environment(AccountsStore.self) private var accountsStore

    private var loader: InactiveProductsLoader { account.inactiveProductsLoader }

    var body: some View {
        VStack(spacing: 12) {
            switch loader.phase {
            // Itens persistidos de uma abertura anterior já chegam prontos no `init` do loader,
            // mas a fase continua `.idle` até `load()` ser chamado de novo — sem esse caso, a tela
            // ficava presa num spinner pra sempre nesse cenário (o `.task` abaixo, corretamente,
            // não chama `load()` de novo só porque já tem itens).
            case .idle where !loader.items.isEmpty:
                selectionBar
                list
            case .idle:
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            case .loadingPage(let page, let total) where loader.items.isEmpty:
                Spacer()
                ProgressView("carregando página \(page) de \(total)…")
                    .frame(maxWidth: .infinity)
                Spacer()
            case .loadingPage, .finished:
                if loader.items.isEmpty {
                    ContentUnavailableView(
                        "nenhum produto inativo",
                        systemImage: "archivebox",
                        description: Text("não há produtos inativos nessa loja agora.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    selectionBar
                    list
                }
            case .failed(let message):
                ContentUnavailableView(
                    "não deu pra carregar os inativos",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxHeight: .infinity)
                Button("tentar de novo") { loader.load() }
                    .buttonStyle(.bordered)
            }
        }
        // Só busca sozinho quando ainda não tem nada — nem carregado agora, nem persistido de uma
        // abertura anterior do app — e só quando essa aba é de fato exibida (a view nem é
        // construída enquanto "publicados" estiver selecionado).
        .task {
            guard loader.items.isEmpty, loader.phase == .idle else { return }
            loader.load()
        }
    }

    private var selectionBar: some View {
        HStack {
            Button(isSelecting ? "cancelar seleção" : "selecionar") {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            }
            .buttonStyle(.bordered)

            Spacer()

            if isSelecting, !selectedIDs.isEmpty {
                Button("republicar \(selectedIDs.count) produtos") {
                    republicarSelecionados()
                }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
    }

    private var list: some View {
        List(loader.items) { product in
            InactiveProductRowView(
                product: product,
                isSelecting: isSelecting,
                isSelected: selectedIDs.contains(product.id),
                onToggleSelection: { toggleSelection(productID: product.id) }
            )
        }
        .listStyle(.plain)
    }

    private func toggleSelection(productID: Int) {
        if selectedIDs.contains(productID) {
            selectedIDs.remove(productID)
        } else {
            selectedIDs.insert(productID)
        }
    }

    /// A fila só usa `id` (pra ler o template de novo) e `title` (pra exibir) — o resto do
    /// `EnjoeiProduct` não importa aqui, então fica com valores neutros.
    private func republicarSelecionados() {
        for product in loader.items where selectedIDs.contains(product.id) {
            let placeholder = EnjoeiProduct(
                id: product.id,
                title: product.title,
                path: product.path,
                photoPublicID: nil,
                currentPrice: product.price,
                originalPrice: product.price
            )
            accountsStore.postQueue.enqueue(product: placeholder, source: account, destination: account)
        }
        selectedIDs.removeAll()
        isSelecting = false
    }
}
