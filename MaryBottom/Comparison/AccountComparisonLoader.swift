import Foundation
import Observation

/// Conduz a comparação entre duas contas: busca a lista de produtos à venda de cada uma direto da
/// rota pública (sem passar pelo megafone) e roda o casamento por similaridade.
@MainActor
@Observable
final class AccountComparisonLoader {
    enum Phase: Equatable, Sendable {
        case idle
        /// Soma das duas contas — cada uma informa seu próprio `loaded`/`total` conforme pagina.
        case loadingProducts(loaded: Int, total: Int)
        case finished(AccountComparisonResult)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?

    /// Progresso de cada conta, separado, pra uma não sobrescrever o total da outra ao atualizar
    /// `phase` — combinado a cada `updateLoadingPhase()`.
    private var loadedA = 0
    private var totalA = 0
    private var loadedB = 0
    private var totalB = 0

    func compare(accountA: AccountSession, accountB: AccountSession) {
        guard task == nil else { return }
        loadedA = 0
        totalA = 0
        loadedB = 0
        totalB = 0
        phase = .loadingProducts(loaded: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(accountA: accountA, accountB: accountB)
            self?.task = nil
        }
    }

    /// Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(accountA: AccountSession, accountB: AccountSession) async {
        // Busca a lista de produtos direto do cliente, sem passar por `MegaphoneRunner.load` —
        // aquele fluxo também confere a exposição de cada produto (chamada extra, via WebView, em
        // lotes) pro megafone, o que aqui só deixa a comparação lenta à toa: ela nunca usa
        // exposição, só o título de cada produto pra casar os pares.
        //
        // Busca sempre fresco em vez de reaproveitar `runner.items`: aquela lista pode estar
        // desatualizada (de uma rodada de megafone antiga, ou persistida de uma sessão passada), e
        // "comparar" é um pedido explícito do usuário pelo estado atual das duas lojas — sem isso,
        // um produto ativado/editado depois do último carregamento aparece como "não encontrado" só
        // por causa do cache.
        //
        // As duas contas em paralelo (`async let`) — cada uma tem sua própria WebView/sessão, sem
        // estado compartilhado entre elas, e isso corta o tempo de espera praticamente pela metade.
        async let productsATask = loadAllProducts(sellerID: accountA.user.id, client: accountA.client) { [weak self] loaded, total in
            self?.loadedA = loaded
            self?.totalA = total
            self?.updateLoadingPhase()
        }
        async let productsBTask = loadAllProducts(sellerID: accountB.user.id, client: accountB.client) { [weak self] loaded, total in
            self?.loadedB = loaded
            self?.totalB = total
            self?.updateLoadingPhase()
        }
        let productsA = (try? await productsATask) ?? []
        let productsB = (try? await productsBTask) ?? []

        // O(N×M) pares — tira do MainActor pra não travar a tela numa loja grande.
        let result = await Task.detached {
            AccountProductMatcher.compare(productsA: productsA, productsB: productsB)
        }.value
        phase = .finished(result)
    }

    private func updateLoadingPhase() {
        phase = .loadingProducts(loaded: loadedA + loadedB, total: totalA + totalB)
    }

    /// - Parameter onProgress: quantos produtos já vieram e o total esperado, depois de cada
    ///   página — a rota `searchProductsForStore` não devolve `pageInfo`, só um `total` por página,
    ///   por isso o progresso só fica preciso quando a primeira página já chegou.
    private func loadAllProducts(
        sellerID: Int,
        client: EnjoeiClientProtocol,
        onProgress: @MainActor (_ loaded: Int, _ total: Int) -> Void
    ) async throws -> [EnjoeiProduct] {
        var products: [EnjoeiProduct] = []
        var seenIDs: Set<Int> = []
        var cursor: String?

        while true {
            try Task.checkCancellation()
            let page = try await client.storeProductsPage(sellerID: sellerID, after: cursor)
            let newProducts = page.products.filter { seenIDs.insert($0.id).inserted }
            products.append(contentsOf: newProducts)
            onProgress(products.count, max(page.total, products.count))

            // Sem cursor novo, sem produto inédito, ou cursor repetido: acabou a loja.
            guard let endCursor = page.endCursor, !newProducts.isEmpty, endCursor != cursor else {
                return products
            }
            cursor = endCursor
        }
    }
}
