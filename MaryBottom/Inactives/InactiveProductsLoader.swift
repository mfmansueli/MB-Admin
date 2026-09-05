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

    private func run() async {
        do {
            // Página 1 sempre sozinha — só ela revela `maxPage`, então não tem o que paralelizar
            // antes dela. Só limpa o que essa conta tinha persistido depois dela chegar de
            // verdade — se a rede falhar logo aqui (`catch` abaixo), o cache antigo em disco
            // continua intacto.
            phase = .loadingPage(1, of: 1)
            let first = try await client.inactiveProductsPage(page: 1)
            itemsPersistence.clearItems()
            itemsPersistence.appendPage(first.products, startingAt: 0)
            var collected = first.products
            items = collected
            let maxPage = first.maxPage

            var nextPage = 2
            while nextPage <= maxPage {
                try Task.checkCancellation()
                let chunkEnd = min(nextPage + pageConcurrency - 1, maxPage)
                let pageNumbers = Array(nextPage...chunkEnd)
                phase = .loadingPage(chunkEnd, of: maxPage)
                // Todo o pedaço em paralelo — pedidos concorrentes não terminam na ordem que
                // foram disparados, então reordena por número de página antes de gravar, pra
                // `appendPage(startingAt:)` continuar em sequência e a lista exibida continuar na
                // ordem certa da loja.
                let results = try await withThrowingTaskGroup(of: (Int, [InactiveProduct]).self) { group in
                    for pageNumber in pageNumbers {
                        group.addTask { [client] in
                            let page = try await client.inactiveProductsPage(page: pageNumber)
                            return (pageNumber, page.products)
                        }
                    }
                    var collectedResults: [(Int, [InactiveProduct])] = []
                    for try await result in group {
                        collectedResults.append(result)
                    }
                    return collectedResults.sorted { $0.0 < $1.0 }
                }
                for (_, products) in results {
                    itemsPersistence.appendPage(products, startingAt: collected.count)
                    collected += products
                }
                items = collected
                nextPage = chunkEnd + 1
                if nextPage <= maxPage, delayBetweenPages > .zero {
                    try await Task.sleep(for: delayBetweenPages)
                }
            }
            phase = .finished
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
