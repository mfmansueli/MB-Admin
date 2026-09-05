import SwiftUI

/// Detalhe de um par "produtos em comum": título e descrição lado a lado, e as palavras
/// (normalizadas) que só aparecem de um lado — o que exatamente puxou o `%` de similaridade pra
/// baixo de 100%. `ProductMatchDifference` (calculado aqui dentro, não antes) é quem faz a conta.
struct ProductMatchDifferenceSheet: View {
    let match: ProductMatch
    @Environment(\.dismiss) private var dismiss

    private var difference: ProductMatchDifference { ProductMatchDifference(match: match) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("similaridade")
                        Spacer()
                        Text("\(Int((match.similarity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("título") {
                    Text(match.productA.title)
                    Text(match.productB.title)
                }

                if match.productA.description != nil || match.productB.description != nil {
                    Section("descrição") {
                        Text(match.productA.description ?? "sem descrição buscada")
                            .foregroundStyle(match.productA.description == nil ? .secondary : .primary)
                        Text(match.productB.description ?? "sem descrição buscada")
                            .foregroundStyle(match.productB.description == nil ? .secondary : .primary)
                    }
                }

                if !difference.onlyInA.isEmpty {
                    Section("só no primeiro") {
                        wordsWrap(difference.onlyInA)
                    }
                }
                if !difference.onlyInB.isEmpty {
                    Section("só no segundo") {
                        wordsWrap(difference.onlyInB)
                    }
                }
                if difference.onlyInA.isEmpty, difference.onlyInB.isEmpty {
                    Section {
                        Text("nenhuma palavra diferente — o texto comparado é idêntico dos dois lados.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("diferenças do par")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar ("fe...") no Mac (idiom otimizado) —
                    // mesmo padrão de `AccountComparisonView` — sem isso, o botão encolhe pro
                    // tamanho de uma "pill" fixa em vez de acompanhar o texto.
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
            }
        }
    }

    /// Palavras já normalizadas (minúsculas, sem acento, no singular) — é o texto exato que entrou
    /// no cálculo, não o texto original do anúncio.
    private func wordsWrap(_ words: [String]) -> some View {
        Text(words.joined(separator: ", "))
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    let productA = EnjoeiProduct(
        id: 1,
        title: "brinco oval zircônia lavanda cravejado - prata 925",
        path: "brinco-1",
        photoPublicID: nil,
        currentPrice: 100,
        originalPrice: 100
    ).withDescription("brinco oval zircônia lavanda cravejado com zircônia crystal - prata 925\ncódigo: x379249\npeso: 2.6 gramas o par")
    let productB = EnjoeiProduct(
        id: 2,
        title: "brinco oval zircônia lavanda cravejado - prata 925",
        path: "brinco-2",
        photoPublicID: nil,
        currentPrice: 100,
        originalPrice: 100
    ).withDescription("brinco oval zircônia lavanda cravejado com zircônia crystal - prata 925\ncódigo: x379249\npeso: 1 grama o par")
    Color.clear
        .sheet(isPresented: .constant(true)) {
            ProductMatchDifferenceSheet(match: ProductMatch(productA: productA, productB: productB, similarity: 0.92))
        }
}
