import SwiftUI

/// Conteúdo da aba "desconto": produtos da conta que pedem a decisão de desconto pra alcançar
/// exposição máxima no megafone.
struct DiscountCandidatesListView: View {
    let loader: DiscountCandidatesLoader
    let sellerID: Int

    var body: some View {
        switch loader.phase {
        case .idle:
            ContentUnavailableView {
                Label("conferir produtos", systemImage: "tag")
            } description: {
                Text("busca na loja quais produtos pedem desconto pra alcançar exposição máxima.")
            } actions: {
                Button("conferir produtos") { loader.load(sellerID: sellerID) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxHeight: .infinity)

        case .loadingProducts(let loaded, let total):
            progressView(headline: total > 0 ? "buscando produtos… \(loaded) de \(total)" : "buscando produtos…")

        case .checkingExposure(let checked, let total):
            progressView(
                headline: "conferindo quais pedem desconto… \(checked) de \(total)",
                progress: total > 0 ? Double(checked) / Double(total) : nil
            )

        case .loaded where loader.candidates.isEmpty:
            ContentUnavailableView(
                "nenhum produto pede desconto agora",
                systemImage: "checkmark.circle",
                description: Text("toque em atualizar pra conferir de novo.")
            )
            .frame(maxHeight: .infinity)
            .toolbar { refreshButton }

        case .loaded:
            List(loader.candidates) { candidate in
                DiscountCandidateRowView(candidate: candidate, loader: loader)
            }
            .listStyle(.plain)
            .toolbar { refreshButton }

        case .failed(let message):
            ContentUnavailableView {
                Label("não consegui conferir", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("tentar de novo") { loader.load(sellerID: sellerID) }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func progressView(headline: String, progress: Double? = nil) -> some View {
        VStack(spacing: 12) {
            Text(headline)
                .font(.subheadline.weight(.medium))
            if let progress {
                ProgressView(value: progress)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                loader.load(sellerID: sellerID)
            } label: {
                Label("atualizar", systemImage: "arrow.clockwise")
            }
            .disabled(loader.isLoading)
        }
    }
}
