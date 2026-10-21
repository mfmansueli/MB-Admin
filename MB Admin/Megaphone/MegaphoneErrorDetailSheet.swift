import SwiftUI

/// Sheet com o erro completo de uma ação que falhou (megafonar, postar, apagar, inativar ou
/// ativar) — a row só mostra até duas linhas da mensagem (ícone ou texto vermelho, os dois abrem
/// isso). Além do texto inteiro sem truncar, mostra o diagnóstico técnico completo por trás dessa
/// mensagem curta (`detail`, quando disponível) — pra ajudar a resolver o problema depois, não só
/// entender o que já apareceu na tela.
struct MegaphoneErrorDetailSheet: View {
    let product: EnjoeiProduct
    let message: String
    /// `nil` quando a falha é antiga demais pra ter diagnóstico guardado (uma entrada de histórico
    /// gravada antes dessa propriedade existir) — nesse caso o sheet só mostra a mensagem curta,
    /// como sempre mostrou.
    var detail: MegaphoneFailureDetail?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProductPhotoView(product: product, size: 64)
                    Text(product.title)
                        .productTitleFont()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.statusFailure)
                    Text(message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let detail {
                        Divider()
                        technicalDetails(detail)
                    }
                    Spacer()
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
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
                if let detail {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: detail.shareText) {
                            Label("compartilhar diagnóstico", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .presentationDetents(detail == nil ? [.medium] : [.medium, .large])
    }

    /// Tudo que dá pra saber sobre o erro de verdade, além da mensagem curta acima — pensado pra
    /// resolver o problema depois (ex.: colando isso numa conversa sobre o bug), não pro dia a dia
    /// de quem só quer saber por que um produto falhou agora.
    @ViewBuilder
    private func technicalDetails(_ detail: MegaphoneFailureDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("diagnóstico técnico")
                .font(.subheadline.weight(.semibold))
            detailRow(label: "ação", value: detail.action.label)
            detailRow(label: "quando", value: detail.occurredAt.formatted(date: .abbreviated, time: .standard))
            if let httpStatus = detail.httpStatus {
                detailRow(label: "status HTTP", value: String(httpStatus))
            }
            if let serverMessage = detail.serverMessage {
                detailRow(label: "resposta do servidor", value: serverMessage)
            }
            detailRow(label: "descrição técnica", value: detail.technicalDescription)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospaced())
        }
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
                message: "o enjoei respondeu com erro 504.",
                detail: MegaphoneFailureDetail(
                    action: .megaphone,
                    error: EnjoeiError.http(status: 504, message: "o enjoei respondeu com erro 504.")
                )
            )
        }
}
