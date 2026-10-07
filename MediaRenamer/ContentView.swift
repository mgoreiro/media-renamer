import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var library = LibraryModel()
    @State private var pickerItem: MediaItem?
    @State private var isApplying = false
    @State private var searchTask: Task<Void, Never>?
    @State private var progress: (done: Int, total: Int)?

    private let engine = RenameEngine()

    private var isBusy: Bool { searchTask != nil }

    var body: some View {
        VStack(spacing: 16) {
            if settings.apiKey.isEmpty {
                Label("Configura tu API key de TMDb en Ajustes (⌘,) antes de buscar coincidencias.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            DropZoneView { urls in
                library.add(urls)
            }

            if library.items.isEmpty {
                Spacer()
                Text("Los ficheros que sueltes aparecerán aquí")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(library.items) { item in
                        FileRowView(item: item, onPickMatch: { pickerItem = item },
                                    onRemove: { library.remove(item) })
                    }
                }
                .listStyle(.inset)

                footer
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: openFiles) {
                    Label("Abrir…", systemImage: "folder")
                }
                .keyboardShortcut("o")
                .help("Añadir ficheros o carpetas (⌘O)")
            }
            ToolbarItem(placement: .automatic) {
                if isBusy {
                    Button { searchTask?.cancel() } label: {
                        Label("Cancelar búsqueda", systemImage: "stop.circle")
                    }
                } else {
                    Button(action: startSearch) {
                        Label("Buscar coincidencias", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("r")
                    .disabled(!canSearch)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { engine.renameAll(library.items) } label: {
                    Label("Renombrar todos", systemImage: "checkmark.circle")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!library.hasRenameableItems || isBusy)
            }
            ToolbarItem(placement: .automatic) {
                Button { engine.undoAll(library.items) } label: {
                    Label("Deshacer renombrado", systemImage: "arrow.uturn.backward")
                }
                .disabled(!library.hasUndoableItems || isBusy)
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    searchTask?.cancel()
                    library.clear()
                } label: {
                    Label("Limpiar", systemImage: "trash")
                }
                .disabled(library.items.isEmpty)
            }
        }
        .sheet(item: $pickerItem) { item in
            MatchPickerSheet(item: item, engine: engine, isApplying: isApplying) { candidate in
                guard !isApplying else { return }
                isApplying = true
                Task {
                    await engine.select(candidate: candidate, for: item, manual: true)
                    await engine.propagateToSeries(from: item, candidate: candidate, in: library.items)
                    isApplying = false
                    pickerItem = nil
                }
            } onCancel: {
                pickerItem = nil
            }
        }
    }

    private var canSearch: Bool {
        !settings.apiKey.isEmpty && library.items.contains { $0.status.isSearchable }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            if let progress, isBusy {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .frame(width: 140)
                Text("Buscando \(progress.done)/\(progress.total)")
            } else {
                let ready = library.items.filter { $0.status == .autoMatched }.count
                let pending = library.items.filter { $0.status == .needsSelection }.count
                Text("\(library.items.count) ficheros · \(ready) listos · \(pending) por elegir")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func startSearch() {
        guard searchTask == nil else { return }
        searchTask = Task {
            await engine.searchAll(library.items) { done, total in
                progress = (done, total)
            }
            searchTask = nil
            progress = nil
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Elige ficheros de vídeo o carpetas"
        guard panel.runModal() == .OK else { return }
        library.add(panel.urls.flatMap { MediaFileScanner.expand($0) })
    }
}

#Preview {
    ContentView()
}
