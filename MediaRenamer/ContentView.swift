import SwiftUI

struct ContentView: View {
    @AppStorage("tmdbAPIKey") private var apiKey: String = ""
    @StateObject private var library = LibraryModel()
    @State private var pickerItem: MediaItem?
    @State private var isBusy = false

    private var engine: RenameEngine { RenameEngine(apiKey: apiKey) }

    var body: some View {
        VStack(spacing: 16) {
            if apiKey.isEmpty {
                Label("Configura tu API key de TMDb en Ajustes (⌘,) antes de buscar coincidencias.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundColor(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
            }

            DropZoneView { urls in
                library.add(urls)
            }

            if library.items.isEmpty {
                Spacer()
                Text("Los ficheros que sueltes aparecerán aquí")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(library.items) { item in
                        FileRowView(item: item) {
                            pickerItem = item
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await searchAll() }
                } label: {
                    Label("Buscar coincidencias", systemImage: "magnifyingglass")
                }
                .disabled(library.items.isEmpty || apiKey.isEmpty || isBusy)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    renameAll()
                } label: {
                    Label("Renombrar todos", systemImage: "checkmark.circle")
                }
                .disabled(!library.hasRenameableItems)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    library.clear()
                } label: {
                    Label("Limpiar", systemImage: "trash")
                }
                .disabled(library.items.isEmpty)
            }
        }
        .sheet(item: $pickerItem) { item in
            MatchPickerSheet(item: item, engine: engine) { candidate in
                Task {
                    let engine = self.engine
                    await engine.select(candidate: candidate, for: item)
                    await engine.propagateToSeries(from: item, candidate: candidate, in: library.items)
                    pickerItem = nil
                }
            } onCancel: {
                pickerItem = nil
            }
        }
    }

    private func searchAll() async {
        isBusy = true
        await engine.searchAllGrouped(library.items)
        isBusy = false
    }

    private func renameAll() {
        let engine = self.engine
        for item in library.items where item.status == .autoMatched {
            engine.rename(item)
        }
    }
}

#Preview {
    ContentView()
}
