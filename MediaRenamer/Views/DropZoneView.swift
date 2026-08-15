import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Arrastra aquí episodios o películas")
                        .font(.headline)
                    Text("Se aceptan ficheros y carpetas")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
            .frame(minHeight: 140)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        var collected: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    collected.append(contentsOf: expandIfNeeded(url))
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            onDrop(collected)
        }
    }

    /// Si el usuario suelta una carpeta, recoge recursivamente los ficheros de vídeo que contiene.
    private func expandIfNeeded(_ url: URL) -> [URL] {
        let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "mov", "m4v", "wmv", "ts"]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }

        if isDir.boolValue {
            var results: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let fileURL as URL in enumerator {
                    if videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                        results.append(fileURL)
                    }
                }
            }
            return results
        } else {
            return videoExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }
    }
}
