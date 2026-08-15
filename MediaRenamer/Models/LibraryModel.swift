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
        let existing = Set(items.map { $0.originalURL })
        var newItems: [MediaItem] = []
        for url in urls where !existing.contains(url) {
            let parsed = FilenameParser.parse(filename: url.lastPathComponent)
            newItems.append(MediaItem(url: url, parsed: parsed))
        }
        for item in newItems {
            cancellables[item.id] = item.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        items.append(contentsOf: newItems)
    }

    func clear() {
        items.removeAll()
        cancellables.removeAll()
    }

    var hasRenameableItems: Bool {
        items.contains { $0.status == .autoMatched }
    }
}
