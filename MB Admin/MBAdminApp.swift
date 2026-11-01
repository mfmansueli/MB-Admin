import SwiftUI

@main
struct MBAdminApp: App {
    /// As contas só abrem com os dados do aparelho legíveis — ver `ProtectedDataGate`. Até lá (só no
    /// prewarm de um aparelho recém-ligado e ainda bloqueado, sem ninguém olhando a tela), a janela
    /// fica vazia.
    @State private var accountsStoreGate = ProtectedDataGate(
        isProtectedDataAvailable: { @MainActor in Self.isProtectedDataAvailable() },
        make: { @MainActor in Self.makeAccountsStore() }
    )
    @Environment(\.scenePhase) private var scenePhase

    /// Em DEBUG, `-demo-mode` troca as contas de verdade pelas inventadas de `DemoMode` (simulador e
    /// testes de UI). Em Release esse caminho nem compila.
    private static func makeAccountsStore() -> AccountsStore {
        #if DEBUG
        if DemoMode.isEnabled {
            return DemoMode.makeAccountsStore()
        }
        #endif
        return AccountsStore()
    }

    /// No Mac não existe esse bloqueio antes do primeiro desbloqueio — e um `false` por engano lá
    /// deixaria a janela vazia pra sempre.
    private static func isProtectedDataAvailable() -> Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        UIApplication.shared.isProtectedDataAvailable
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let accountsStore = accountsStoreGate.value {
                    ContentView()
                        .environment(accountsStore)
                } else {
                    Color(uiColor: .systemBackground)
                }
            }
            // O aviso do sistema cobre o desbloqueio com o app vivo em segundo plano; a volta pra
            // frente cobre o caso de o aviso ter chegado com o processo suspenso.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                accountsStoreGate.openIfPossible()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { accountsStoreGate.openIfPossible() }
            }
            // O app inteiro usa estilos de fonte do sistema (headline, caption etc.), então
            // isso escala todo o texto de uma vez, sem mexer view por view. `.xxxLarge` é o
            // maior tamanho antes das categorias de acessibilidade (que exigiriam revisar
            // layouts mais apertados, tipo o segmented picker e os badges de desconto).
            //
            // No Mac (idiom otimizado) esse modificador não tem efeito nenhum — testado com
            // `.xSmall`, `.accessibility1` e `.accessibility5` e o texto saiu bit-a-bit igual
            // nas três vezes. O Mac idiom do Catalyst simplesmente ignora Dynamic Type; não é
            // bug daqui, é limitação da plataforma quando "Optimize Interface for Mac" está
            // ligado.
            .dynamicTypeSize(.xxxLarge)
        }
    }
}
