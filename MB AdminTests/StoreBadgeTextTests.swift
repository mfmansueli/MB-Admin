import Foundation
import Testing
@testable import MB_Admin

@Suite("etiqueta da loja no topo do detalhe da conta")
struct StoreBadgeTextTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("o nome da conta vira \"loja <nome>\"")
    func nomeDaLoja() {
        #expect(StoreBadgeText.storeName("Mary") == "loja Mary")
        #expect(StoreBadgeText.storeName("Antônia") == "loja Antônia")
        #expect(StoreBadgeText.storeName("  Iago ") == "loja Iago")
    }

    @Test("nome que já começa com \"loja\" não ganha outro na frente")
    func semLojaDobrado() {
        #expect(StoreBadgeText.storeName("loja B") == "loja B")
        #expect(StoreBadgeText.storeName("Loja da Mary") == "Loja da Mary")
        #expect(StoreBadgeText.storeName("LOJA") == "LOJA")
        // Só a palavra inteira — "lojinha" é outro nome.
        #expect(StoreBadgeText.storeName("lojinha") == "loja lojinha")
    }

    @Test("a hora do recarregar vem com data e hora, com zero à esquerda")
    func horaDoRecarregar() {
        let now = date(2026, 11, 1, 19, 0)
        #expect(StoreBadgeText.refreshTime(date(2026, 11, 1, 18, 33), now: now, calendar: calendar) == "01/11 às 18:33")
        #expect(StoreBadgeText.refreshTime(date(2026, 3, 9, 7, 5), now: now, calendar: calendar) == "09/03 às 07:05")
        // Sempre com a data, mesmo ontem — nada de "ontem".
        #expect(StoreBadgeText.refreshTime(date(2026, 10, 31, 23, 59), now: now, calendar: calendar) == "31/10 às 23:59")
    }

    @Test("de outro ano, a data ganha o ano")
    func outroAno() {
        let now = date(2026, 1, 2, 10, 0)
        #expect(StoreBadgeText.refreshTime(date(2025, 12, 28, 9, 5), now: now, calendar: calendar) == "28/12/25 às 09:05")
    }

    @Test("a hora segue o fuso do calendário, não UTC")
    func fuso() {
        // 21:33 UTC é 18:33 em São Paulo.
        let utc = Date(timeIntervalSince1970: 1_793_568_780) // 2026-11-01 21:33 UTC
        #expect(StoreBadgeText.refreshTime(utc, now: utc, calendar: calendar) == "01/11 às 18:33")
    }

    @Test("VoiceOver lê a loja e quando o catálogo foi atualizado; sem recarregar nunca, só a loja")
    func acessibilidade() {
        let now = date(2026, 11, 1, 19, 0)
        #expect(
            StoreBadgeText.accessibilityLabel(
                name: "Mary", refreshedAt: date(2026, 11, 1, 18, 33), now: now, calendar: calendar
            ) == "loja Mary, catálogo atualizado em 01/11 às 18:33"
        )
        #expect(StoreBadgeText.accessibilityLabel(name: "loja B", refreshedAt: nil) == "loja B")
    }
}
