import Foundation

/// Quem descreve "de qual conta pra qual" uma ação de fila (postar/repostar/apagar/inativar/
/// ativar) foi ou está sendo feita — `PostQueueItem` (ainda na fila) e `PostHistoryEntry` (já
/// concluído) têm exatamente os mesmos campos de conta, então a frase é montada uma vez só aqui.
protocol AccountActionDescribing {
    var kind: PostQueueItem.Kind { get }
    var sourceAccountID: EnjoeiAccountID { get }
    var sourceAccountName: String { get }
    var destinationAccountID: EnjoeiAccountID { get }
    var destinationAccountName: String { get }
}

extension AccountActionDescribing {
    /// Republicar na mesma conta (origem == destino) fica "republicando X" — "de X para X" é
    /// tecnicamente certo, mas confuso de ler. Apagar/inativar/ativar só têm uma conta envolvida,
    /// então nem entram nessa comparação.
    var originDestinationLine: String {
        switch kind {
        case .delete:
            return "apagando de \(sourceAccountName)"
        case .inactivate:
            return "inativando de \(sourceAccountName)"
        case .activate:
            return "ativando de \(sourceAccountName)"
        case .post:
            if sourceAccountID == destinationAccountID {
                return "republicando em \(sourceAccountName)"
            }
            return "de \(sourceAccountName) para \(destinationAccountName)"
        }
    }
}
