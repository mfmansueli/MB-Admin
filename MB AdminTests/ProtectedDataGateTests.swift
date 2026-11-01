import Foundation
import Testing
@testable import MB_Admin

@Suite("abrir as contas só com os dados do aparelho legíveis")
struct ProtectedDataGateTests {
    private final class Token {}

    /// Referência, não `var` solta: o portão guarda as closures (isoladas na principal), e mudar uma
    /// variável capturada por elas depois é justamente o que o compilador reclama.
    private final class Device {
        var isProtectedDataAvailable = false
        var makeCount = 0
    }

    @Test("aparelho desbloqueado: abre na hora, sem quadro vazio")
    func abreNaHora() {
        let device = Device()
        device.isProtectedDataAvailable = true
        let gate = ProtectedDataGate(isProtectedDataAvailable: { device.isProtectedDataAvailable }, make: {
            device.makeCount += 1
            return Token()
        })

        #expect(gate.value != nil)
        #expect(device.makeCount == 1)
    }

    @Test("ainda bloqueado desde que ligou: não cria nada, nem tentando de novo")
    func bloqueadoNaoCria() {
        let device = Device()
        let gate = ProtectedDataGate(isProtectedDataAvailable: { device.isProtectedDataAvailable }, make: {
            device.makeCount += 1
            return Token()
        })

        gate.openIfPossible()

        #expect(gate.value == nil)
        #expect(device.makeCount == 0)
    }

    @Test("desbloqueou: abre uma vez só, e as próximas chamadas mantêm a mesma instância")
    func abreUmaVezDepoisDoDesbloqueio() {
        let device = Device()
        let gate = ProtectedDataGate(isProtectedDataAvailable: { device.isProtectedDataAvailable }, make: {
            device.makeCount += 1
            return Token()
        })

        device.isProtectedDataAvailable = true
        gate.openIfPossible()
        let first = gate.value
        gate.openIfPossible()
        device.isProtectedDataAvailable = false
        gate.openIfPossible()

        #expect(first != nil)
        #expect(gate.value === first)
        #expect(device.makeCount == 1)
    }
}
