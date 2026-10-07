import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Arrastra aquí episodios o películas")
                        .font(.headline)
                    Text("Se aceptan ficheros y carpetas (o usa Abrir… con ⌘O)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
            .frame(minHeight: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zona para soltar ficheros o carpetas de vídeo")
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let accepted = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !accepted.isEmpty else { return false }

        // Los callbacks llegan en hilos arbitrarios: el acceso a `collected` se serializa con un lock.
        let lock = NSLock()
        var collected: [URL] = []
        let group = DispatchGroup()

        for provider in accepted {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let found = MediaFileScanner.expand(url)
                lock.lock()
                collected.append(contentsOf: found)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let result = collected
            lock.unlock()
            onDrop(result)
        }
        return true
    }
}
