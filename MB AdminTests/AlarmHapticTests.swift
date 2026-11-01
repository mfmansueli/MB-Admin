import CoreHaptics
import Foundation
import Testing
@testable import MB_Admin

@Suite("vibração de alarme")
struct AlarmHapticTests {
    @Test("três batidas, um zumbido longo e mais duas — tudo na intensidade máxima")
    func eventosDoAlarme() {
        let events = AlarmHaptic.events()

        #expect(events.map(\.type) == [
            .hapticTransient, .hapticTransient, .hapticTransient,
            .hapticContinuous,
            .hapticTransient, .hapticTransient
        ])
        for event in events {
            let intensity = event.eventParameters.first { $0.parameterID == .hapticIntensity }?.value
            #expect(intensity == 1)
        }
        #expect(events.map(\.relativeTime) == events.map(\.relativeTime).sorted())
    }

    @Test("dura por volta de um segundo e vira um padrão válido")
    func padraoValido() throws {
        let pattern = try AlarmHaptic.pattern()

        #expect(pattern.duration > 0.9)
        #expect(pattern.duration < 1.2)
    }
}
