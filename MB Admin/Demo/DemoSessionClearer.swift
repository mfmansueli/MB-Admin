#if DEBUG
import Foundation

/// Sair de uma conta no `DemoMode` não tem cookie nenhum pra apagar.
@MainActor
final class DemoSessionClearer: EnjoeiSessionClearing {
    func clearSession() async {}
}
#endif
