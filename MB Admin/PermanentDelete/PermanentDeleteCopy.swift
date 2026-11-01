import Foundation

/// Textos da confirmação de apagar produto de verdade — o anúncio sai da loja no enjoei, não só do
/// app. Os mesmos pra linha (menu "..." de publicados e inativos) e pra seleção em massa das duas
/// abas, de propósito alarmantes: é a única ação do app sem volta, e fica longe de "limpar fila"
/// (a vassoura da fila de ações), que só mexe na fila e nunca na loja.
nonisolated enum PermanentDeleteCopy {
    static let confirmButtonLabel = "apagar permanentemente"

    static func title(productCount: Int) -> String {
        productCount == 1
            ? "⚠️ apagar este produto da loja para sempre?"
            : "⚠️ apagar \(productCount) produtos da loja para sempre?"
    }

    static func message(productCount: Int) -> String {
        let warning = "não é só tirar do app ou da fila."
        return productCount == 1
            ? "atenção: o anúncio vai ser excluído permanentemente na raiz da sua loja no enjoei — \(warning) "
                + "depois de apagado, não tem como recuperar."
            : "atenção: os \(productCount) anúncios vão ser excluídos permanentemente na raiz da sua loja no enjoei — \(warning) "
                + "depois de apagados, não tem como recuperar nenhum."
    }
}
