import Foundation
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Pede, atualiza e encerra a Live Activity de cada conta megafonando — a tela bloqueada e a
/// Dynamic Island mostram "12 de 340" com pausar/parar, sem abrir o app. Alimentado pelo resumo da
/// rodada (`MegaphoneRunner.onProgressSnapshotChange`), então acompanha o mesmo lote que a lista de
/// contas: muda a cada fase e a cada `progressSnapshotBatchSize` produtos, não a cada um.
///
/// No Mac não faz nada: ActivityKit não existe no Catalyst.
@MainActor
final class MegaphoneLiveActivities {
    /// Quanto tempo a atividade de uma rodada já encerrada continua na tela bloqueada, com o
    /// resultado, antes de sumir sozinha.
    private static let finishedDismissalDelay: TimeInterval = 10 * 60

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private var activities: [EnjoeiAccountID: Activity<MegaphoneActivityAttributes>] = [:]
    private var lastContent: [EnjoeiAccountID: MegaphoneActivityContent] = [:]
    #endif

    init() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        // Sobras de uma execução anterior (o app fechado no meio de uma rodada): a rodada não
        // existe mais, então a atividade só mentiria na tela bloqueada.
        for activity in Activity<MegaphoneActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    func apply(_ snapshot: MegaphoneProgressSnapshot, accountID: EnjoeiAccountID, accountName: String) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        let content = MegaphoneActivityContent(snapshot: snapshot)
        switch MegaphoneLiveActivityStep.step(for: snapshot.phase, hasActivity: activities[accountID] != nil) {
        case .start:
            start(content, accountID: accountID, accountName: accountName)
        case .update:
            update(content, accountID: accountID)
        case .end:
            end(content, accountID: accountID)
        case .none:
            break
        }
        #endif
    }

    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private func start(_ content: MegaphoneActivityContent, accountID: EnjoeiAccountID, accountName: String) {
        // Desligado nos Ajustes (ou num aparelho sem Live Activities): o megafone segue normal.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activities[accountID] = try Activity.request(
                attributes: MegaphoneActivityAttributes(accountID: accountID, accountName: accountName),
                content: ActivityContent(state: content, staleDate: nil)
            )
            lastContent[accountID] = content
        } catch {
            // Sem atividade (limite de atividades simultâneas, por exemplo) — a rodada não depende
            // dela; a próxima mudança de fase tenta de novo.
        }
    }

    private func update(_ content: MegaphoneActivityContent, accountID: EnjoeiAccountID) {
        guard let activity = activities[accountID], lastContent[accountID] != content else { return }
        lastContent[accountID] = content
        Task { await activity.update(ActivityContent(state: content, staleDate: nil)) }
    }

    private func end(_ content: MegaphoneActivityContent, accountID: EnjoeiAccountID) {
        guard let activity = activities.removeValue(forKey: accountID) else { return }
        lastContent[accountID] = nil
        let dismissal = Date.now.addingTimeInterval(Self.finishedDismissalDelay)
        Task { await activity.end(ActivityContent(state: content, staleDate: nil), dismissalPolicy: .after(dismissal)) }
    }
    #endif
}
