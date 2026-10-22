#if DEBUG
import Foundation

/// Modo de demonstração (só em DEBUG): abre o app com as contas e produtos inventados de
/// `DemoCatalog`, sem tocar no Enjoei — pra conferir o visual de cada estado no simulador e pros
/// testes de UI, que não têm como logar numa conta de verdade. Ligado pelo argumento de lançamento
/// `-demo-mode`; sem ele, nada daqui roda.
@MainActor
enum DemoMode {
    static let launchArgument = "-demo-mode"

    /// Junto de `-demo-mode`, já abre a primeira conta — pra reproduzir no Mac o que acontece ao
    /// entrar numa conta sem precisar clicar (testes de UI no Mac mexem no cursor de verdade).
    static let openFirstAccountArgument = "-demo-open-first-account"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static var initialSelectedAccountID: EnjoeiAccountID? {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains(openFirstAccountArgument) else { return nil }
        return DemoCatalog.profiles.first?.accountID
    }

    static func makeAccountsStore() -> AccountsStore {
        // Cada abertura começa do zero (lista de produtos, inativos, preço esperto, filtro
        // escolhido), pra o que um teste de UI vê não depender do que a abertura anterior deixou
        // em disco.
        for profile in DemoCatalog.profiles {
            PerAccountModelContainer.destroy(for: profile.accountID)
            UserDefaults.standard.removeObject(forKey: AccountProductFilter.storageKey(for: profile.accountID))
            UserDefaults.standard.removeObject(forKey: SmartPriceStatusFilter.storageKey(for: profile.accountID))
        }
        return AccountsStore(
            dependenciesFactory: { accountID in
                AccountDependencies(
                    client: DemoEnjoeiClient(profile: DemoCatalog.profile(for: accountID)),
                    sessionClearer: DemoSessionClearer(),
                    webView: nil
                )
            },
            persistence: DemoAccountsPersistence(),
            postHistoryPersistence: InMemoryPostHistoryPersistence(),
            postQueueItemsPersistence: InMemoryPostQueueItemsPersistence()
        )
    }
}
#endif
