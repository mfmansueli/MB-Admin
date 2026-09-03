import Foundation
import SwiftData

/// Registro SwiftData de uma entrada de histórico — guarda `PostHistoryEntry` inteiro já
/// codificado em `payload` (em vez de espelhar cada campo como propriedade do modelo) pra não
/// duplicar `EnjoeiProduct`/`PostQueueItem.Kind`/`EnjoeiAccountID` como um segundo esquema
/// paralelo. `id` e `completedAt` ficam de fora do blob só para permitir unicidade e ordenação
/// sem decodificar tudo.
@Model
final class PostHistoryRecord {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var payload: Data

    init(id: UUID, completedAt: Date, payload: Data) {
        self.id = id
        self.completedAt = completedAt
        self.payload = payload
    }
}
