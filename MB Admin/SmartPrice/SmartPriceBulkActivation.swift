import Foundation

/// "ativar em N" da aba "sem preço esperto", fora da seleção: o que aparece na lista (filtro e busca
/// já aplicados) e ainda pode ser ativado, com os textos da barra e do alerta. O uso de sempre é
/// escolher um filtro (quase sempre "preço atual") e ativar em todos — sem passar pela seleção, que
/// continua lá pra escolher só alguns.
///
/// Fica de fora quem está bloqueado (a API recusa a ação), quem já ganhou o preço esperto e quem
/// está na fila de ativar agora (`SmartPriceProductsLoader.activationStatuses` em `.pending` — só
/// gravado ao entrar na fila — ou `.megaphoning`). Quem falhou antes entra de novo.
nonisolated struct SmartPriceBulkActivation: Equatable, Sendable {
    let eligibleIDs: [Int]
    let blockedCount: Int
    /// Da lista à vista, quantos ainda estão na fila de ativar ou ativando agora.
    let activatingCount: Int
    let filter: SmartPriceStatusFilter
    let isSearching: Bool

    init(
        items: [SmartPriceListItem],
        filter: SmartPriceStatusFilter,
        activationStatuses: [Int: MegaphoneStatus],
        isSearching: Bool
    ) {
        var eligibleIDs: [Int] = []
        var blockedCount = 0
        var activatingCount = 0
        for item in items {
            let status = activationStatuses[item.id]
            if status == .pending || status == .megaphoning {
                activatingCount += 1
            } else if item.product.blocked {
                blockedCount += 1
            } else if !item.product.smartPriceEnabled, status != .succeeded {
                eligibleIDs.append(item.id)
            }
        }
        self.eligibleIDs = eligibleIDs
        self.blockedCount = blockedCount
        self.activatingCount = activatingCount
        self.filter = filter
        self.isSearching = isSearching
    }

    var count: Int { eligibleIDs.count }
    var isActivating: Bool { activatingCount > 0 }

    /// "6 produtos com preço atual" — sem o "com …" no filtro "todos". Enquanto a fila anda,
    /// "ativando… faltam 5".
    var title: String {
        if isActivating {
            return "ativando… faltam \(activatingCount.formatted())"
        }
        guard count > 0 else { return "nada pra ativar\(filterScope)" }
        return "\(Self.products(count))\(filterScope)"
    }

    var subtitle: String {
        if isActivating {
            return "um de cada vez, acompanhe pelo ícone de cada linha"
        }
        if blockedCount > 0 {
            return blockedCount == 1
                ? "1 bloqueado fica de fora"
                : "\(blockedCount.formatted()) bloqueados ficam de fora"
        }
        return isSearching ? "só os da busca" : "só os que aparecem na lista"
    }

    /// Uma linha só, pro subtítulo da barra de navegação no iPhone (lá não tem a barra de vidro com
    /// as duas linhas): o título, mais quantos bloqueados ficam de fora.
    var compactSummary: String {
        guard !isActivating, blockedCount > 0 else { return title }
        let blocked = blockedCount == 1 ? "1 bloqueado" : "\(blockedCount.formatted()) bloqueados"
        return "\(title) · \(blocked)"
    }

    var buttonLabel: String {
        count > 0 ? "ativar em \(count.formatted())" : "ativar"
    }

    var confirmationTitle: String {
        "ativar preço esperto em \(Self.products(count))\(filterScope)?"
    }

    var confirmationMessage: String {
        let base = "cada anúncio é ativado um de cada vez, com um intervalo entre um e o próximo — "
            + "acompanhe o andamento pelo ícone de cada linha."
        switch blockedCount {
        case 0: return base
        case 1: return "\(base) 1 produto bloqueado fica de fora."
        default: return "\(base) \(blockedCount.formatted()) produtos bloqueados ficam de fora."
        }
    }

    private var filterScope: String {
        filter == .all ? "" : " com \(filter.label)"
    }

    private static func products(_ count: Int) -> String {
        count == 1 ? "1 produto" : "\(count.formatted()) produtos"
    }
}
