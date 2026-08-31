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

/// Manual porque a associated value de `.failed` impede a síntese automática — só usado pra
/// persistir a lista carregada em disco.
nonisolated extension MegaphoneStatus: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "pending": self = .pending
        case "megaphoning": self = .megaphoning
        case "succeeded": self = .succeeded
        case "failed": self = .failed(try container.decode(String.self, forKey: .message))
        default: self = .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending: try container.encode("pending", forKey: .kind)
        case .megaphoning: try container.encode("megaphoning", forKey: .kind)
        case .succeeded: try container.encode("succeeded", forKey: .kind)
        case .failed(let message):
            try container.encode("failed", forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}
