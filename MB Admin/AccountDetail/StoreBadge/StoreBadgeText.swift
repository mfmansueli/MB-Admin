import Foundation

/// Os textos da etiqueta da loja no topo do detalhe da conta ("loja Mary · ↻ 01/11 às 18:33") —
/// puros, pra `StoreBadge` só montar.
nonisolated enum StoreBadgeText {
    /// "loja Mary" — sem dobrar o "loja" quando o nome da conta já começa com ela ("loja B").
    static func storeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        let alreadyNamesTheStore = firstWord.compare(
            "loja",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) == .orderedSame
        return alreadyNamesTheStore ? trimmed : "loja \(trimmed)"
    }

    /// Data e hora do último toque em "recarregar produtos": "01/11 às 18:33". Sempre com a data
    /// (não "hoje"/"ontem") — foi o que o usuário pediu; o ano só aparece quando não é o de agora
    /// ("28/12/25 às 09:05"), pra não gastar largura à toa numa etiqueta que já disputa espaço com
    /// o nome da loja.
    static func refreshTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = parts.day ?? 0
        let month = parts.month ?? 0
        let year = parts.year ?? 0
        var datePart = String(format: "%02d/%02d", day, month)
        if year != calendar.component(.year, from: now) {
            datePart += String(format: "/%02d", year % 100)
        }
        let timePart = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return "\(datePart) às \(timePart)"
    }

    /// O VoiceOver lê a etiqueta inteira de uma vez, dizendo o que é a hora (na tela, só o ícone de
    /// recarregar diz): "loja Mary, catálogo atualizado em 01/11 às 18:33". Sem nunca ter
    /// recarregado, só a loja.
    static func accessibilityLabel(
        name: String,
        refreshedAt: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let store = storeName(name)
        guard let refreshedAt else { return store }
        return "\(store), catálogo atualizado em \(refreshTime(refreshedAt, now: now, calendar: calendar))"
    }
}
