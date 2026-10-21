#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import Foundation

/// O pausar/continuar da Live Activity do megafone — roda no processo do app (`LiveActivityIntent`),
/// sem abrir o app na frente.
struct ToggleMegaphonePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "pausar ou continuar o megafone"

    @Parameter(title: "conta")
    var accountID: String

    init() {}

    init(accountID: UUID) {
        self.accountID = accountID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: accountID) {
            MegaphoneLiveActivityCommands.shared.send(.togglePause, accountID: id)
        }
        return .result()
    }
}
#endif
