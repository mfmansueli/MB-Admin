import Foundation
import SwiftData

/// Um `ModelContainer` só pra todo o app — todo `@Model` mora aqui dentro, mesmo que cada
/// persistência (`SwiftDataPostHistoryPersistence`, `SwiftDataInactiveProductsPersistence`,
/// `SwiftDataSmartPriceProductsPersistence`, `SwiftDataMegaphoneItemsPersistence`) só mexa no seu
/// próprio tipo.
///
/// Crítico: sem `url` explícita, `ModelConfiguration` grava no mesmo arquivo padrão
/// (`Application Support/default.store`) não importa quais tipos entrem no `Schema` — então quatro
/// containers separados, cada um com só o seu tipo no schema, todos acabavam apontando pro mesmo
/// arquivo em disco com visões incompatíveis do que existe nele. Cada abertura de container
/// "esquecia" as tabelas dos outros três, e abrir vários ao mesmo tempo (várias contas restauradas
/// em paralelo no boot, cada uma criando seus três containers) corrompia o SQLite embaixo —
/// exatamente o erro "no such table" que apareceu no console. `static let`, computado uma vez só e
/// cacheado, garante que só existe UM container de verdade no processo inteiro.
nonisolated enum SharedModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            PostHistoryRecord.self,
            InactiveProductRecord.self,
            SmartPriceProductRecord.self,
            MegaphoneItemRecord.self
        ])
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)])
    }()
}
