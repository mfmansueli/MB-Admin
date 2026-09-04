import Foundation
import SwiftData

/// Um `ModelContainer` só pra dado que cruza conta — hoje, só `PostHistoryRecord` (o histórico de
/// ações da fila é intencionalmente global, não por conta). As três listas por conta
/// (`InactiveProductRecord`/`SmartPriceProductRecord`/`MegaphoneItemRecord`) moraram aqui antes, mas
/// migraram pra um container próprio por conta — ver `PerAccountModelContainer`.
///
/// Crítico: sem `url` explícita, `ModelConfiguration` grava no mesmo arquivo padrão
/// (`Application Support/default.store`) não importa quais tipos entrem no `Schema` — então
/// containers separados, cada um com só o seu tipo no schema, acabavam apontando pro mesmo arquivo
/// em disco com visões incompatíveis do que existe nele. Cada abertura de container "esquecia" as
/// tabelas dos outros, e abrir vários ao mesmo tempo corrompia o SQLite embaixo — exatamente o erro
/// "no such table" que já apareceu no console uma vez. `static let`, computado uma vez só e
/// cacheado, garante que só existe UM container de verdade no processo inteiro pra esse schema.
nonisolated enum SharedModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([PostHistoryRecord.self])
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }()
}
