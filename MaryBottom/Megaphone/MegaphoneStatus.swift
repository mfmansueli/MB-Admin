import Foundation

/// Situação de um produto dentro de uma rodada de megafone.
nonisolated enum MegaphoneStatus: Equatable, Sendable {
    case pending
    case megaphoning
    case succeeded
    case failed(String)

    var isFinished: Bool {
        switch self {
        case .succeeded, .failed: true
        case .pending, .megaphoning: false
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
