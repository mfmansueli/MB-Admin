import Foundation

/// Como o Enjoei classifica a exposição de um produto no megafone — decide se vale a pena oferecer
/// desconto pra alcançar exposição máxima. Valores documentados pelo próprio front do Enjoei
/// (módulo Vuex `megaphone`).
nonisolated enum MegaphoneExposureKind: Equatable, Sendable {
    /// Já tem exposição máxima de graça — megafona direto, sem mexer no preço.
    case maximumForFree
    /// Só alcança exposição máxima se der desconto.
    case maximumAfterDiscount
    /// De graça fica com exposição reduzida; com desconto vai pra máxima.
    case reducedForFreeOrMaximumAfterDiscount
    /// De graça só sobra exposição reduzida — não tem opção de desconto pra melhorar.
    case reducedForFree
    /// Exposição máxima de graça, mas só mudando de plano.
    case maximumForFreeAfterChangePlan
    /// Valor que o Enjoei ainda não documentou pra gente — não quebra a leitura do resto do lote.
    case other(String)

    /// A regra prática do spec: só esses dois casos "pedem" a decisão de desconto.
    var requiresDiscountDecision: Bool {
        switch self {
        case .maximumAfterDiscount, .reducedForFreeOrMaximumAfterDiscount: true
        case .maximumForFree, .reducedForFree, .maximumForFreeAfterChangePlan, .other: false
        }
    }
}

nonisolated extension MegaphoneExposureKind: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "maximum_for_free": self = .maximumForFree
        case "maximum_after_discount": self = .maximumAfterDiscount
        case "reduced_for_free_or_maximum_after_discount": self = .reducedForFreeOrMaximumAfterDiscount
        case "reduced_for_free": self = .reducedForFree
        case "maximum_for_free_after_change_plan": self = .maximumForFreeAfterChangePlan
        default: self = .other(raw)
        }
    }
}
