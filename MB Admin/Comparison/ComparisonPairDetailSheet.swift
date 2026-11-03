import SwiftUI

/// Detalhe de um par, pra revisar: as fotos que ligaram os dois lado a lado (grandes), o estado e
/// todos os motivos, título/descrição dos dois e as palavras que só aparecem de um lado — e as
/// decisões: confirmar "mesmo produto", marcar "produtos diferentes", corrigir ou desfazer uma
/// revisão já feita. A revisão só existe por um toque aqui (ou na linha) — nada automático vira
/// decisão.
struct ComparisonPairDetailSheet: View {
    let match: ProductMatch
    let accountAName: String
    let accountBName: String
    let onDecide: (ComparisonDecision.Verdict) -> Void
    let onUndo: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var difference: ProductMatchDifference { ProductMatchDifference(match: match) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    photos
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                }

                Section(match.statusText) {
                    ForEach(match.reasons, id: \.self) { reason in
                        Text(reason.text)
                    }
                    if match.reasons.isEmpty {
                        Text("nenhuma foto liga os dois")
                            .foregroundStyle(.secondary)
                    }
                }

                decisionSection

                Section("título") {
                    labeled(accountAName, match.productA.title)
                    labeled(accountBName, match.productB.title)
                }

                if match.productA.description != nil || match.productB.description != nil {
                    Section("descrição") {
                        labeled(accountAName, match.productA.description ?? "sem descrição buscada")
                        labeled(accountBName, match.productB.description ?? "sem descrição buscada")
                    }
                }

                if !difference.onlyInA.isEmpty {
                    Section("só em \(accountAName)") {
                        wordsWrap(difference.onlyInA)
                    }
                }
                if !difference.onlyInB.isEmpty {
                    Section("só em \(accountBName)") {
                        wordsWrap(difference.onlyInB)
                    }
                }
            }
            .navigationTitle("detalhes do par")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar no Mac (idiom otimizado).
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
            }
        }
    }

    private var photos: some View {
        HStack(alignment: .top, spacing: 12) {
            photoColumn(match.displayPhotoA, store: accountAName, title: match.productA.title)
            photoColumn(match.displayPhotoB, store: accountBName, title: match.productB.title)
        }
        .frame(maxWidth: .infinity)
    }

    private func photoColumn(_ publicID: String?, store: String, title: String) -> some View {
        VStack(spacing: 6) {
            ProductPhotoView(
                photoURL: publicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .card) },
                largePhotoURL: publicID.flatMap { EnjoeiPhoto.url(publicID: $0, size: .card) },
                title: title,
                size: 140
            )
            Text(store)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var decisionSection: some View {
        Section {
            switch match.status {
            case .strong, .needsReview:
                decisionButton("é o mesmo produto", systemImage: "equal.circle", verdict: .sameProduct)
                decisionButton("são produtos diferentes", systemImage: "nosign", verdict: .differentProducts)
            case .confirmed:
                decisionButton("na verdade são diferentes", systemImage: "nosign", verdict: .differentProducts)
                undoButton
            case .rejected:
                decisionButton("na verdade é o mesmo produto", systemImage: "equal.circle", verdict: .sameProduct)
                undoButton
            }
        } footer: {
            Text("sua revisão fica salva pra este par e vale nas próximas comparações, até um dos anúncios mudar de capa ou de título.")
        }
    }

    private func decisionButton(_ title: String, systemImage: String, verdict: ComparisonDecision.Verdict) -> some View {
        Button {
            onDecide(verdict)
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private var undoButton: some View {
        Button {
            onUndo()
            dismiss()
        } label: {
            Label("desfazer revisão", systemImage: "arrow.uturn.backward")
        }
    }

    private func labeled(_ store: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
        }
    }

    /// Palavras já normalizadas (minúsculas, sem acento, no singular) — é o texto exato que entrou
    /// na comparação, não o texto original do anúncio.
    private func wordsWrap(_ words: [String]) -> some View {
        Text(words.joined(separator: ", "))
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
