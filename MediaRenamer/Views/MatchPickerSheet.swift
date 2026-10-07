import SwiftUI

struct MatchPickerSheet: View {
    @ObservedObject var item: MediaItem
    var engine: RenameEngine
    /// Mientras se aplica la elección (y se propaga a la serie) la lista se bloquea.
    var isApplying: Bool
    var onSelect: (TMDbCandidate) -> Void
    var onCancel: () -> Void

    @State private var searchText: String = ""
    /// `nil` = aún no se ha hecho una búsqueda manual.
    @State private var manualResults: [TMDbCandidate]?
    @State private var isSearching = false
    @State private var searchError: String?

    private var candidates: [TMDbCandidate] { manualResults ?? item.candidates }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Elige la coincidencia correcta")
                .font(.headline)
            Text(item.originalURL.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)

            if item.kind == .episode {
                Label("Se aplicará automáticamente al resto de episodios de esta serie",
                      systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Buscar en TMDb…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runManualSearch() }
                Button("Buscar") { runManualSearch() }
                    .disabled(isSearching || searchText.isEmpty)
            }

            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ZStack {
                List {
                    ForEach(candidates) { candidate in
                        Button { onSelect(candidate) } label: { row(candidate) }
                            .buttonStyle(.plain)
                    }
                }
                .disabled(isApplying)
                .opacity(isApplying ? 0.4 : 1)

                if isSearching || isApplying {
                    ProgressView(isApplying ? "Aplicando…" : "Buscando…")
                } else if candidates.isEmpty {
                    Text(manualResults == nil ? "No hay candidatos. Prueba a buscar a mano."
                                              : "Sin resultados para esa búsqueda.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isApplying)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { searchText = item.parsedTitle }
    }

    private func row(_ candidate: TMDbCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: candidate.posterURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 36, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayTitle).fontWeight(.medium)
                if !candidate.overview.isEmpty {
                    Text(candidate.overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func runManualSearch() {
        guard !searchText.isEmpty, !isSearching else { return }
        isSearching = true
        searchError = nil
        let text = searchText
        let isEpisode = item.kind == .episode
        Task {
            do {
                let client = engine.client
                let results = isEpisode ? try await client.searchTV(title: text, year: nil)
                                        : try await client.searchMovie(title: text, year: nil)
                manualResults = results
            } catch {
                searchError = error.localizedDescription
            }
            isSearching = false
        }
    }
}
