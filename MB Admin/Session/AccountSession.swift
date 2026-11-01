import Foundation
import Observation
import WebKit

/// Uma conta logada: identidade, sessão do Enjoei e o megafone dela. Nasce uma vez por conta dentro
/// do `AccountsStore` e vive enquanto a conta existir na lista — é o mesmo objeto observado pela row
/// compacta na lista de contas e pela tela de detalhe, para o progresso do megafone continuar
/// visível mesmo com a tela de detalhe fechada.
@MainActor
@Observable
final class AccountSession: Identifiable {
    let id: EnjoeiAccountID
    private(set) var user: EnjoeiUser
    private(set) var status: AccountSessionStatus = .active
    private(set) var lastRoundSummary: MegaphoneRoundSummary?
    /// Quando o usuário tocou em "recarregar produtos" pela última vez (ver `reloadAllProducts`) —
    /// é o que a etiqueta da loja mostra no iPhone (`StoreBadge`). O carregamento automático de
    /// quando a conta ainda não tem nada não conta: só o toque.
    private(set) var lastCatalogRefresh: Date?
    /// Chamado a cada recarregar, pra quem guarda o `record` em disco (`AccountsStore`) — mesmo
    /// esquema de `MegaphoneRunner.onRoundFinished`.
    var onCatalogRefreshed: (() -> Void)?

    let client: EnjoeiClientProtocol
    let runner: MegaphoneRunner
    let keepAlive: MegaphoneKeepAlive
    let inactiveProductsLoader: InactiveProductsLoader
    let smartPriceProductsLoader: SmartPriceProductsLoader
    let productDetailsLoader: ProductDetailsLoader
    let webView: WKWebView?

    private let sessionClearer: EnjoeiSessionClearing

    /// - Parameter megaphoneQueue: a fila compartilhada de verdade vem de `AccountsStore.megaphoneQueue`
    ///   — a produção sempre passa a mesma instância pras contas restantes; testes/previews recebem
    ///   uma fila só sua por padrão (nunca espera, já que está sozinha nela).
    init(
        id: EnjoeiAccountID,
        user: EnjoeiUser,
        lastRoundSummary: MegaphoneRoundSummary? = nil,
        lastCatalogRefresh: Date? = nil,
        dependencies: AccountDependencies,
        megaphoneQueue: MegaphoneQueue = MegaphoneQueue()
    ) {
        self.id = id
        self.user = user
        self.lastRoundSummary = lastRoundSummary
        self.lastCatalogRefresh = lastCatalogRefresh
        client = dependencies.client
        sessionClearer = dependencies.sessionClearer
        webView = dependencies.webView

        // Compartilhado entre o runner e `productDetailsLoader`: os dois lêem/escrevem a mesma
        // tabela de produtos publicados (um a lista inteira, o outro só a descrição de cada um) —
        // duas instâncias apontando pro mesmo `ModelContainer` funcionam, mas reusar uma só evita
        // abrir um segundo `ModelContext`/repetir a migração de esquema à toa.
        let megaphoneItemsPersistence = SwiftDataMegaphoneItemsPersistence(accountID: id)
        let runner = MegaphoneRunner(
            client: dependencies.client,
            itemsPersistence: megaphoneItemsPersistence,
            megaphoneQueue: megaphoneQueue
        )
        self.runner = runner
        keepAlive = MegaphoneKeepAlive(runner: runner)
        inactiveProductsLoader = InactiveProductsLoader(
            client: dependencies.client,
            itemsPersistence: SwiftDataInactiveProductsPersistence(accountID: id)
        )
        smartPriceProductsLoader = SmartPriceProductsLoader(
            client: dependencies.client,
            itemsPersistence: SwiftDataSmartPriceProductsPersistence(accountID: id)
        )
        // A API de preço esperto não devolve título (só id/preço) — quem sabe o nome é a aba
        // "publicados" (`runner.items`). `weak`: o closure não precisa manter o runner vivo, ele já
        // vive tanto quanto esta `AccountSession` de qualquer forma.
        smartPriceProductsLoader.titleResolver = { [weak runner] productID in
            runner?.items.first { $0.product.id == productID }?.product.title
        }

        let productDetailsLoader = ProductDetailsLoader(
            client: dependencies.client,
            itemsPersistence: megaphoneItemsPersistence
        )
        // A descrição buscada não tem pra onde ir sozinha — este loader só busca e persiste, quem
        // atualiza a lista ao vivo (pra a tela e a comparação enxergarem sem reabrir o app) é o
        // runner. `weak`: mesmo raciocínio do `titleResolver` acima.
        productDetailsLoader.onDescriptionFetched = { [weak runner] productID, description in
            runner?.applyDescription(productID: productID, description: description)
        }
        self.productDetailsLoader = productDetailsLoader
    }

    var record: AccountRecord {
        AccountRecord(id: id, user: user, lastRoundSummary: lastRoundSummary, lastCatalogRefresh: lastCatalogRefresh)
    }

    func refreshUser(_ user: EnjoeiUser) {
        self.user = user
        status = .active
    }

    func markSessionExpired() {
        status = .sessionExpired
    }

    func markCheckFailed() {
        status = .checkFailed
    }

    /// Recarrega as abas do detalhe todas juntas, não só a que está na tela — publicados busca a
    /// loja de novo do zero, já com a exposição de cada produto (o que decide "pedem desconto"),
    /// inativos e preço esperto refazem as páginas (é o único jeito de tentar de novo manualmente,
    /// além do "tentar de novo" que só aparece quando dá erro de verdade). Não mexe nos publicados
    /// com uma rodada em aberto (`MegaphoneRunner.reload` ignora — e o botão já fica desabilitado
    /// nesse caso).
    ///
    /// Guarda a hora do toque em `lastCatalogRefresh` — a do toque, não a de quando as três
    /// terminam, que é o que o usuário pediu pra etiqueta da loja mostrar.
    func reloadAllProducts(now: Date = .now) {
        runner.reload(sellerID: user.id)
        inactiveProductsLoader.load()
        smartPriceProductsLoader.load()
        lastCatalogRefresh = now
        onCatalogRefreshed?()
    }

    func applyRoundFinished(_ summary: MegaphoneRoundSummary) {
        lastRoundSummary = summary
    }

    func clearSession() async {
        await sessionClearer.clearSession()
    }
}
