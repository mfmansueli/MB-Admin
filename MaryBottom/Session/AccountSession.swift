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

    let client: EnjoeiClientProtocol
    let runner: MegaphoneRunner
    let keepAlive: MegaphoneKeepAlive
    let inactiveProductsLoader: InactiveProductsLoader
    let smartPriceProductsLoader: SmartPriceProductsLoader
    let webView: WKWebView?

    private let sessionClearer: EnjoeiSessionClearing

    init(
        id: EnjoeiAccountID,
        user: EnjoeiUser,
        lastRoundSummary: MegaphoneRoundSummary? = nil,
        dependencies: AccountDependencies
    ) {
        self.id = id
        self.user = user
        self.lastRoundSummary = lastRoundSummary
        client = dependencies.client
        sessionClearer = dependencies.sessionClearer
        webView = dependencies.webView

        let runner = MegaphoneRunner(
            client: dependencies.client,
            accountID: id,
            itemsPersistence: SwiftDataMegaphoneItemsPersistence()
        )
        self.runner = runner
        keepAlive = MegaphoneKeepAlive(runner: runner)
        inactiveProductsLoader = InactiveProductsLoader(
            client: dependencies.client,
            accountID: id,
            itemsPersistence: SwiftDataInactiveProductsPersistence()
        )
        smartPriceProductsLoader = SmartPriceProductsLoader(
            client: dependencies.client,
            accountID: id,
            itemsPersistence: SwiftDataSmartPriceProductsPersistence()
        )
        // A API de preço esperto não devolve título (só id/preço) — quem sabe o nome é a aba
        // "publicados" (`runner.items`). `weak`: o closure não precisa manter o runner vivo, ele já
        // vive tanto quanto esta `AccountSession` de qualquer forma.
        smartPriceProductsLoader.titleResolver = { [weak runner] productID in
            runner?.items.first { $0.product.id == productID }?.product.title
        }
    }

    var record: AccountRecord {
        AccountRecord(id: id, user: user, lastRoundSummary: lastRoundSummary)
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

    func applyRoundFinished(_ summary: MegaphoneRoundSummary) {
        lastRoundSummary = summary
    }

    func clearSession() async {
        await sessionClearer.clearSession()
    }
}
