import Foundation

/// O que a comparação usa além das duas contas: o cache/análise de fotos (compartilhado entre todas
/// as lojas) e as revisões manuais. Um só por app (`AccountsStore.comparisonServices`); testes e
/// modo de demonstração usam a versão em memória.
@MainActor
struct ComparisonServices {
    let photoSignatures: PhotoSignatureLoader
    let decisions: ComparisonDecisionStoring

    static func live() -> ComparisonServices {
        ComparisonServices(
            photoSignatures: PhotoSignatureLoader(
                fetcher: EnjoeiPhotoBytesFetcher(),
                store: SwiftDataPhotoSignatureStore(modelContainer: SharedModelContainer.shared)
            ),
            decisions: SwiftDataComparisonDecisionStore()
        )
    }

    static func inMemory(
        fetcher: PhotoBytesFetching = EnjoeiPhotoBytesFetcher(),
        store: PhotoSignatureStoring = InMemoryPhotoSignatureStore(),
        decisions: ComparisonDecisionStoring? = nil
    ) -> ComparisonServices {
        ComparisonServices(
            photoSignatures: PhotoSignatureLoader(fetcher: fetcher, store: store, retryDelay: .zero),
            decisions: decisions ?? InMemoryComparisonDecisionStore()
        )
    }
}
