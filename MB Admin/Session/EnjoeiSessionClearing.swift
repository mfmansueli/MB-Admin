import Foundation

/// Quem sabe apagar a sessão do Enjoei no logout. Protocolo para os testes não dependerem do WebKit.
@MainActor
protocol EnjoeiSessionClearing {
    func clearSession() async
}
