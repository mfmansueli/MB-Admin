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
        /// Só na "comparação completa" (ver `compare(fullComparison:)`) — as duas contas buscam a
        /// descrição de cada produto ao mesmo tempo; cada `AccountSession.productDetailsLoader` tem
        /// seu próprio `phase`, que a tela lê direto pra mostrar o progresso individual de cada
        /// loja.
        case fetchingDetails
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

    /// - Parameter fullComparison: além do título, busca a descrição de cada produto das duas
    ///   contas (`ProductDetailsLoader`, ao mesmo tempo pras duas) antes de casar os pares — mais
    ///   precisa, mas uma chamada de rede por produto, sem lote, então pode demorar bastante numa
    ///   loja grande.
    func compare(accountA: AccountSession, accountB: AccountSession, fullComparison: Bool = false) {
        guard task == nil else { return }
        loadedA = 0
        totalA = 0
        loadedB = 0
        totalB = 0
        phase = .loadingProducts(loaded: 0, total: 0)
        task = Task { [weak self] in
            await self?.run(accountA: accountA, accountB: accountB, fullComparison: fullComparison)
            self?.task = nil
        }
    }

    /// Serve aos testes; a tela só observa `phase`.
    func waitUntilFinished() async {
        await task?.value
    }

    private func run(accountA: AccountSession, accountB: AccountSession, fullComparison: Bool) async {
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
        var productsA = (try? await productsATask) ?? []
        var productsB = (try? await productsBTask) ?? []

        if fullComparison {
            await fetchDetails(productsA: productsA, accountA: accountA, productsB: productsB, accountB: accountB)
        }
        // Sempre usa a descrição que já estiver salva localmente pra cada produto, mesmo com
        // "comparação completa" desligada — não busca nada novo (isso só acontece acima, e só
        // ligado), mas o que uma comparação completa anterior (com qualquer conta) já deixou salvo
        // não devia ficar de fora só porque desta vez o toggle está desligado.
        productsA = applyKnownDescriptions(to: productsA, loader: accountA.productDetailsLoader)
        productsB = applyKnownDescriptions(to: productsB, loader: accountB.productDetailsLoader)

        // O(N×M) pares — tira do MainActor pra não travar a tela numa loja grande.
        let result = await Task.detached {
            AccountProductMatcher.compare(productsA: productsA, productsB: productsB)
        }.value
        phase = .finished(result)
    }

    private func updateLoadingPhase() {
        phase = .loadingProducts(loaded: loadedA + loadedB, total: totalA + totalB)
    }

    /// Dispara a busca de descrição das duas contas ao mesmo tempo (cada `AccountSession` tem seu
    /// próprio `productDetailsLoader`, sessão/`WKWebView` própria — não competem entre si) e espera
    /// as duas terminarem. Não devolve nada: quem chama sempre passa por `applyKnownDescriptions`
    /// logo depois, que já lê o que ficou persistido (incluindo o que acabou de ser buscado aqui).
    private func fetchDetails(
        productsA: [EnjoeiProduct],
        accountA: AccountSession,
        productsB: [EnjoeiProduct],
        accountB: AccountSession
    ) async {
        phase = .fetchingDetails
        accountA.productDetailsLoader.fetchAll(products: productsA)
        accountB.productDetailsLoader.fetchAll(products: productsB)
        await accountA.productDetailsLoader.waitUntilFinished()
        await accountB.productDetailsLoader.waitUntilFinished()
    }

    /// Preenche a descrição de cada produto que já estiver salva localmente pra essa conta —
    /// independente de "comparação completa" estar ligada agora: uma comparação completa anterior
    /// (com qualquer conta) já pode ter deixado a descrição salva, e ela deve valer sempre que
    /// disponível, não só quando o toggle está ligado nesta chamada em particular. Produto sem
    /// descrição continua com `description: nil` — o matcher cai pra título sozinho pra ele.
    private func applyKnownDescriptions(to products: [EnjoeiProduct], loader: ProductDetailsLoader) -> [EnjoeiProduct] {
        let descriptions = loader.knownDescriptions(for: products.map(\.id))
        return products.map { product in
            descriptions[product.id].map(product.withDescription) ?? product
        }
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
