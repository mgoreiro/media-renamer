import SwiftUI

struct MatchPickerSheet: View {
    @ObservedObject var item: MediaItem
    var engine: RenameEngine
    var onSelect: (TMDbCandidate) -> Void
    var onCancel: () -> Void

    @State private var searchText: String = ""
    @State private var manualResults: [TMDbCandidate] = []
    @State private var isSearching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Elige la coincidencia correcta")
                .font(.headline)
            Text(item.originalURL.lastPathComponent)
                .font(.caption)
                .foregroundColor(.secondary)

            if item.kind == .episode {
                Label("Se aplicará automáticamente al resto de episodios de esta serie",
                      systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                TextField("Buscar en TMDb…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runManualSearch() }
                Button("Buscar") { runManualSearch() }
            }

            List {
                let candidates = manualResults.isEmpty ? item.candidates : manualResults
                ForEach(candidates) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.displayTitle).fontWeight(.medium)
                            if !candidate.overview.isEmpty {
                                Text(candidate.overview)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { searchText = item.parsedTitle }
    }

    private func runManualSearch() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        Task {
            let results: [TMDbCandidate]
            do {
                if item.kind == .episode {
                    results = try await engine.client.searchTV(title: searchText, year: nil)
                } else {
                    results = try await engine.client.searchMovie(title: searchText, year: nil)
                }
            } catch {
                results = []
            }
            await MainActor.run {
                manualResults = results
                isSearching = false
            }
        }
    }
}
