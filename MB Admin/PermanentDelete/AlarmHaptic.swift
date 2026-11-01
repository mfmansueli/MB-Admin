import CoreHaptics
import UIKit

/// Vibração de alarme pra quando a confirmação de apagar produto da loja aparece na tela — forte e
/// comprida de propósito, bem diferente dos toques curtos do resto do sistema: três batidas secas,
/// um zumbido pesado e mais duas batidas.
///
/// Só existe em iPhone: iPad e Mac não têm Taptic Engine, e lá `play()` não faz nada.
@MainActor
final class AlarmHaptic {
    static let shared = AlarmHaptic()

    /// Reaproveitado entre um alarme e o próximo; desliga sozinho quando fica parado
    /// (`isAutoShutdownEnabled`) e religa no `start()` do próximo `play()`.
    private var engine: CHHapticEngine?

    func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try engine ?? Self.makeEngine()
            self.engine = engine
            try engine.start()
            try engine.makePlayer(with: Self.pattern()).start(atTime: CHHapticTimeImmediate)
        } catch {
            // Sem o motor (ocupado, servidor de haptics reiniciando), ainda vibra o erro do
            // sistema — mais fraco, mas o aviso não passa em branco.
            self.engine = nil
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    /// Os eventos do alarme, em ordem — ~1s no total.
    nonisolated static func events() -> [CHHapticEvent] {
        let strong = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1)
        let sharp = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
        let dull = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
        func knock(at time: TimeInterval) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [strong, sharp], relativeTime: time)
        }
        return [
            knock(at: 0),
            knock(at: 0.1),
            knock(at: 0.2),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [strong, dull], relativeTime: 0.32, duration: 0.45),
            knock(at: 0.85),
            knock(at: 0.95)
        ]
    }

    nonisolated static func pattern() throws -> CHHapticPattern {
        try CHHapticPattern(events: events(), parameters: [])
    }

    private static func makeEngine() throws -> CHHapticEngine {
        let engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = true
        // O servidor de haptics reiniciou: o motor antigo morreu, o próximo `play()` cria outro.
        // `@Sendable` explícito: o CoreHaptics chama isto numa fila qualquer, nunca na principal.
        engine.resetHandler = { @Sendable in
            Task { @MainActor in AlarmHaptic.shared.engine = nil }
        }
        return engine
    }
}
