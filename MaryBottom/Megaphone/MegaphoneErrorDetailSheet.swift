import SwiftUI

/// Sheet com o erro completo de um megafone que falhou — a row só mostra até duas linhas da
/// mensagem (ícone ou texto vermelho, os dois abrem isso); aqui dá pra ler o texto inteiro, sem
/// truncar.
struct MegaphoneErrorDetailSheet: View {
    let product: EnjoeiProduct
    let message: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProductPhotoView(product: product, size: 64)
                Text(product.title)
                    .productTitleFont()
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .navigationTitle("detalhe do erro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // `.fixedSize()` evita o texto truncar ("fe...") no Mac (idiom otimizado) —
                    // sem isso, o botão encolhe pro tamanho de uma "pill" fixa em vez de acompanhar
                    // o texto.
                    Button("fechar") { dismiss() }
                        .fixedSize()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    Text("linha da lista")
        .sheet(isPresented: .constant(true)) {
            MegaphoneErrorDetailSheet(
                product: EnjoeiProduct(
                    id: 1,
                    title: "anel aro 17 entrelaçado cravejado zircônia branca",
                    path: "anel-1",
                    photoPublicID: nil,
                    currentPrice: 99,
                    originalPrice: 99
                ),
                message: "o enjoei respondeu com erro 504."
            )
        }
}
