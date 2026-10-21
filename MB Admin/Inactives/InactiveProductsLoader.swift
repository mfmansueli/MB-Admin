import Foundation
import Observation

/// Busca todas as páginas de produtos inativos da própria loja, uma vez, guardando o resultado em
/// disco pra não buscar tudo de novo a próxima vez que a aba "inativos" for aberta — molde
/// simplificado do `MegaphoneRunner` (sem rodadas nem pausa, só um carregamento).
@MainActor
@Observable
final class InactiveProductsLoader {
    enum Phase: Equatable, Sendable {
        case idle
        case loadingPage(Int, of: Int)
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [InactiveProduct] = []
    private var task: Task<Void, Never>?

    /// Pra `AccountsStore.isEligibleForMemoryRelease` saber que essa conta está no meio de um
    /// carregamento — `phase` sozinho não dá pra comparar direto porque `.loadingPage` carrega
    /// valores associados.
    var isLoadingPage: Bool {
        if case .loadingPage = phase { return true }
        return false
    }
    /// `var`, não `let`: testes zeram, igual `MegaphoneRunner.delayBetweenProducts` — não faz
    /// sentido esperar de verdade entre páginas da mesma conta num teste.
    var delayBetweenPages: Duration = .milliseconds(300)
    /// Quantas páginas buscar ao mesmo tempo depois da primeira (que revela `maxPage` sozinha,
    /// sem paralelismo possível antes dela) — corta o tempo de abrir a aba pela primeira vez de
    /// ~N × `delayBetweenPages` pra ~(N / pageConcurrency) × `delayBetweenPages` numa loja grande,
    /// sem abrir mão da pausa entre pedidos: ela passa a valer entre PEDAÇOS de páginas, não entre
    /// cada página sozinha — mesmo raciocínio de `MegaphoneRunner.megaphoneBatchChunkSize`. `var`,
    /// não `let`: testes usam um valor pequeno sem depender de dezenas de páginas fake.
    var pageConcurrency = 4

    private let client: EnjoeiClientProtocol
    private let itemsPersistence: InactiveProductsPersisting

    init(
        client: EnjoeiClientProtocol,
        itemsPersistence: InactiveProductsPersisting = InMemoryInactiveProductsPersistence()
    ) {
        self.client = client
        self.itemsPersistence = itemsPersistence
        items = itemsPersistence.loadItems()
    }

    func load() {
        guard task == nil else { return }
        phase = .loadingPage(1, of: 1)
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    /// Busca por título direto na persistência (SwiftData em produção — ver
    /// `SwiftDataInactiveProductsPersistence.search(matching:)`), em vez de filtrar `items` em
    /// memória. Fachada pra `InactiveProductsListView` não precisar conhecer `itemsPersistence`.
    func search(matching query: String, limit: Int = 500) -> [InactiveProduct] {
        itemsPersistence.search(matching: query, limit: limit)
    }

    /// Tira um produto do cache em disco sem mexer em `items` — pra um produto apagado (ver
    /// `PostQueue.deleteAndTrack`) não voltar como inativo na próxima abertura do app, mas a linha
    /// dele continuar na tela, marcada como apagada, até o próximo carregamento (mesmo
    /// comportamento da aba de publicados).
    func removeFromCache(productID: Int) {
        itemsPersistence.removeItem(productID: productID)
    }

    private func run() async {
        do {
            // Página 1 sempre sozinha — nada se sabe da paginação antes dela. Só limpa o que essa
            // conta tinha persistido depois dela chegar de verdade — se a rede falhar logo aqui
            // (`catch` abaixo), o cache antigo em disco continua intacto.
            phase = .loadingPage(1, of: 1)
            let first = try await client.inactiveProductsPage(page: 1)
            itemsPersistence.clearItems()
            var seenIDs = Set<Int>()
            var collected: [InactiveProduct] = []
            appendNewProducts(first.products, to: &collected, seenIDs: &seenIDs)
            items = collected
            // `maxPage` de UMA página é só o maior link de paginação que ela mostra, não o total
            // de verdade: no iPhone/iPad, confiar só no da página 1 parava na página 2 (20
            // inativos) numa loja com muito mais — ao que tudo indica a WebView recebe ali o
            // layout mobile do site, com uma paginação compacta que só aponta pra página
            // seguinte. Por isso o maior número visto em QUALQUER página até agora: no layout
            // desktop (Mac), a página 1 já revela o total e nada muda; numa paginação compacta,
            // cada página revela a seguinte até a última.
            var knownMaxPage = first.maxPage

            var nextPage = 2
            while nextPage <= knownMaxPage {
                try Task.checkCancellation()
                let chunkEnd = min(nextPage + pageConcurrency - 1, knownMaxPage)
                let pageNumbers = Array(nextPage...chunkEnd)
                phase = .loadingPage(chunkEnd, of: knownMaxPage)
                // Todo o pedaço em paralelo — pedidos concorrentes não terminam na ordem que
                // foram disparados, então reordena por número de página antes de gravar, pra
                // `appendPage(startingAt:)` continuar em sequência e a lista exibida continuar na
                // ordem certa da loja.
                let results = try await withThrowingTaskGroup(of: (Int, InactiveProductsPage).self) { group in
                    for pageNumber in pageNumbers {
                        group.addTask { [client] in
                            let page = try await client.inactiveProductsPage(page: pageNumber)
                            return (pageNumber, page)
                        }
                    }
                    var collectedResults: [(Int, InactiveProductsPage)] = []
                    for try await result in group {
                        collectedResults.append(result)
                    }
                    return collectedResults.sorted { $0.0 < $1.0 }
                }
                for (_, page) in results {
                    appendNewProducts(page.products, to: &collected, seenIDs: &seenIDs)
                    knownMaxPage = max(knownMaxPage, page.maxPage)
                }
                items = collected
                nextPage = chunkEnd + 1
                if nextPage <= knownMaxPage, delayBetweenPages > .zero {
                    try await Task.sleep(for: delayBetweenPages)
                }
            }
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Grava e acumula só os produtos ainda não vistos neste carregamento — um produto inativado
    /// no meio dele (megafone/fila rodando junto) empurra a lista da loja uma posição pra frente, e
    /// o último de uma página reaparece como primeiro da seguinte; repetido, quebraria o
    /// `ForEach` da tela (dois itens com o mesmo `id`).
    private func appendNewProducts(
        _ products: [InactiveProduct],
        to collected: inout [InactiveProduct],
        seenIDs: inout Set<Int>
    ) {
        let newProducts = products.filter { seenIDs.insert($0.id).inserted }
        itemsPersistence.appendPage(newProducts, startingAt: collected.count)
        collected += newProducts
    }
}
