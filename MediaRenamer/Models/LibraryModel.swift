import Foundation
import Combine

/// Envuelve la colección de MediaItem y reenvía sus cambios internos
/// (p.ej. al elegir una coincidencia manualmente) para que las vistas
/// que dependen de ese estado, como los botones de la toolbar, se
/// actualicen correctamente.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var items: [MediaItem] = []
    private var cancellables: [UUID: AnyCancellable] = [:]

    func add(_ urls: [URL]) {
        var known = Set(items.map { $0.originalURL.standardizedFileURL })
        var newItems: [MediaItem] = []
        let sorted = urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        for url in sorted where known.insert(url.standardizedFileURL).inserted {
            newItems.append(MediaItem(url: url, parsed: FilenameParser.parse(url: url)))
        }
        for item in newItems {
            cancellables[item.id] = item.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        items.append(contentsOf: newItems)
    }

    func remove(_ item: MediaItem) {
        items.removeAll { $0.id == item.id }
        cancellables[item.id] = nil
    }

    func clear() {
        items.removeAll()
        cancellables.removeAll()
    }

    var hasRenameableItems: Bool {
        items.contains { $0.status == .autoMatched }
    }

    var hasUndoableItems: Bool {
        items.contains { $0.status == .renamed && !$0.renamedOps.isEmpty }
    }
}
