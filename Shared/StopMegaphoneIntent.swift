#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import Foundation

/// O "parar" da Live Activity do megafone — mesmo efeito do "parar" do painel no app: interrompe a
/// rodada no fim do pedaço em voo. Roda no processo do app (`LiveActivityIntent`).
struct StopMegaphoneIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "parar o megafone"

    @Parameter(title: "conta")
    var accountID: String

    init() {}

    init(accountID: UUID) {
        self.accountID = accountID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: accountID) {
            MegaphoneLiveActivityCommands.shared.send(.stop, accountID: id)
        }
        return .result()
    }
}
#endif
