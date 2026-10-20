import Foundation
import SwiftData

/// Um `ModelContainer` próprio por conta, num arquivo próprio — não um índice numa tabela
/// compartilhada, mas isolamento de verdade: a consulta de uma conta nunca chega perto das linhas
/// de outra, então nem precisa de `accountID` como coluna pra filtrar por ela.
///
/// Motivo de existir separado de `SharedModelContainer`: `#Index` (o jeito "normal" de acelerar uma
/// consulta filtrada por conta numa tabela compartilhada) exige iOS 18/macOS 15+, mais novo que o
/// alvo mínimo do Mac Catalyst deste projeto (17.0) — ver `InactiveProductRecord`/
/// `SmartPriceProductRecord`/`MegaphoneItemRecord` antigos. Particionar por conta em arquivos
/// separados entrega o mesmo resultado (nenhuma consulta varre linha de outra conta) sem depender
/// da versão do SO.
///
/// Crítico (mesma lição de `SharedModelContainer`): cada conta usa uma `url` própria e explícita —
/// nunca a localização padrão. Um cache por `accountID`, computado uma vez só por conta, garante que
/// duas instâncias de persistência da MESMA conta (ex.: os três loaders de uma `AccountSession`)
/// sempre abrem o MESMO container, nunca dois containers brigando pelo mesmo arquivo.
@MainActor
enum PerAccountModelContainer {
    private static var containersByAccountID: [EnjoeiAccountID: ModelContainer] = [:]

    static func shared(for accountID: EnjoeiAccountID) -> ModelContainer {
        if let existing = containersByAccountID[accountID] { return existing }
        let schema = Schema([
            InactiveProductRecord.self,
            SmartPriceProductRecord.self,
            MegaphoneItemRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: storeURL(for: accountID))
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        containersByAccountID[accountID] = container
        return container
    }

    /// Chamado no logout — apaga o arquivo inteiro da conta (não só as linhas de dentro dele), pra
    /// não deixar cache órfão em disco pra sempre. Sem problema apagar com o container ainda na
    /// hierarquia de referências de quem está saindo (`AccountsStore.logout`) — remover o arquivo
    /// enquanto um handle aberto existe é comportamento padrão e seguro em POSIX, o processo só não
    /// volta a escrever nele depois.
    static func destroy(for accountID: EnjoeiAccountID) {
        containersByAccountID.removeValue(forKey: accountID)
        let url = storeURL(for: accountID)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }

    private static func storeURL(for accountID: EnjoeiAccountID) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AccountLists", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(accountID.uuidString).store")
    }
}
