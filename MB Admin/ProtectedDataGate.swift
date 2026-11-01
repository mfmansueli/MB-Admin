import Foundation
import Observation

/// Só cria `value` quando os dados protegidos do aparelho já podem ser lidos — e uma vez só.
///
/// Existe por causa do prewarm do iOS: logo depois de ligar o aparelho, ainda bloqueado e sem nunca
/// ter sido desbloqueado, o sistema às vezes abre o app em segundo plano. Nessa hora os arquivos do
/// app continuam criptografados — o SwiftData não abre o banco (e o `fatalError` de
/// `SharedModelContainer` derrubava o app, 4 crashes reais num iPad) e o `UserDefaults` volta vazio
/// (as contas pareceriam não existir). Esperar o desbloqueio evita os dois.
@MainActor
@Observable
final class ProtectedDataGate<Value: AnyObject> {
    private(set) var value: Value?
    @ObservationIgnored private let isProtectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let make: @MainActor () -> Value

    /// Já tenta abrir aqui: no caso normal (app aberto pelo usuário, aparelho desbloqueado), `value`
    /// sai pronto de primeira, sem passar por um quadro vazio.
    init(isProtectedDataAvailable: @escaping @MainActor () -> Bool, make: @escaping @MainActor () -> Value) {
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.make = make
        openIfPossible()
    }

    /// Chamado quando os dados podem ter ficado disponíveis (aviso do sistema, app voltando pra
    /// frente). Não faz nada se ainda estiverem protegidos ou se `value` já existir.
    func openIfPossible() {
        guard value == nil, isProtectedDataAvailable() else { return }
        value = make()
    }
}
