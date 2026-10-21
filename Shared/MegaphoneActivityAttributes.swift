#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

/// A Live Activity de uma rodada do megafone de uma conta — uma por conta megafonando. Fica de pé
/// do toque em "megafonar" até a rodada acabar (ver `MegaphoneLiveActivities`, no app).
///
/// Compartilhado entre o app (que pede, atualiza e encerra) e a extensão `MB Admin LiveActivity`
/// (que desenha). Só iPhone/iPad: ActivityKit não existe no Mac Catalyst.
nonisolated struct MegaphoneActivityAttributes: ActivityAttributes {
    typealias ContentState = MegaphoneActivityContent

    /// Pros botões de pausar/parar (`ToggleMegaphonePauseIntent`/`StopMegaphoneIntent`) saberem
    /// qual conta comandar.
    let accountID: UUID
    let accountName: String
}
#endif
