#if DEBUG
import Foundation

/// Contas salvas do `DemoMode` — começa sempre com as de `DemoCatalog` e não grava nada em disco,
/// pra nunca misturar com as contas de verdade guardadas no `UserDefaults`.
@MainActor
final class DemoAccountsPersistence: AccountsPersisting {
    private var records = DemoCatalog.profiles.map {
        AccountRecord(id: $0.accountID, user: $0.user, lastRoundSummary: $0.lastRoundSummary)
    }

    func loadAccounts() -> [AccountRecord] {
        records
    }

    func save(_ accounts: [AccountRecord]) {
        records = accounts
    }
}
#endif
