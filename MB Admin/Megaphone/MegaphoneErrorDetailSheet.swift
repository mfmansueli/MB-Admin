import SwiftUI

/// Sheet com o erro completo de uma ação que falhou (megafonar, aplicar desconto, postar, apagar,
/// inativar ou ativar) — a row só mostra até duas linhas da mensagem (ícone ou texto vermelho, os
/// dois abrem isso). Em cima, o produto e o que deixou de acontecer; no meio, a mensagem inteira; e
/// embaixo, recolhível, o diagnóstico técnico por trás dela (`detail`, quando disponível) — pra
/// ajudar a resolver o problema depois, não só entender o que já apareceu na tela.
struct MegaphoneErrorDetailSheet: View {
    let product: EnjoeiProduct
    let message: String
    /// `nil` quando a falha é antiga demais pra ter diagnóstico guardado (uma entrada de histórico
    /// gravada antes dessa propriedade existir) — nesse caso o sheet só mostra a mensagem curta,
    /// como sempre mostrou.
    var detail: MegaphoneFailureDetail?
    /// "tentar de novo" — `nil` esconde o botão: no histórico a ação já saiu da fila, e não tem o
    /// que refazer dali.
    var onRetry: (() -> Void)?

    @State private var isShowingDiagnostics = true
    @Environment(\.dismiss) private var dismiss

    private let cardShape = RoundedRectangle(cornerRadius: 26, style: .continuous)
    private let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    productCard
                    Text(message)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(cardBackground, in: cardShape)
                    if let detail {
                        diagnostics(detail)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("detalhe do erro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("fechar", systemImage: "xmark")
                    }
                }
                if let detail {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: detail.shareText) {
                            Label("compartilhar diagnóstico", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .floatingBottomBar { bottomButtons }
        }
        .presentationDetents([.medium, .large])
    }

    private var productCard: some View {
        HStack(spacing: 12) {
            ProductPhotoView(product: product, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.title)
                    .productTitleFont()
                    .lineLimit(3)
                Label(detail?.action.failureHeadline ?? "deu erro", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.statusFailure)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground, in: cardShape)
    }

    /// Tudo que dá pra saber sobre o erro de verdade, além da mensagem acima — pensado pra resolver
    /// o problema depois (ex.: colando isso numa conversa sobre o bug), não pro dia a dia de quem só
    /// quer saber por que um produto falhou agora. Por isso dá pra recolher.
    private func diagnostics(_ detail: MegaphoneFailureDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { isShowingDiagnostics.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isShowingDiagnostics ? 0 : -90))
                    Text("diagnóstico técnico")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.supportingText)
                .padding(.horizontal, 16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isShowingDiagnostics ? "aberto" : "recolhido")

            if isShowingDiagnostics {
                VStack(spacing: 0) {
                    ForEach(Array(detail.diagnosticRows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        diagnosticRow(row)
                    }
                }
                .background(cardBackground, in: cardShape)
                .textSelection(.enabled)
            }
        }
        .padding(.top, 4)
    }

    private func diagnosticRow(_ row: MegaphoneFailureDetail.DiagnosticRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(row.label)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(row.value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bottomButtons: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text("fechar").frame(maxWidth: .infinity)
            }
            .buttonStyle(.neutral(size: 50))
            if let onRetry {
                Button {
                    onRetry()
                    dismiss()
                } label: {
                    Label("tentar de novo", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tinted(.accentColor, size: 50))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
                    error: EnjoeiError.http(status: 504, message: "Gateway Time-out")
                ),
                onRetry: {}
            )
        }
}
