import SwiftUI

struct FileRowView: View {
    @ObservedObject var item: MediaItem
    var onPickMatch: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalURL.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let proposed = item.proposedFilename {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(proposed)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                statusLabel

                if let warning = item.warning {
                    Text(warning).font(.caption).foregroundStyle(.orange)
                }
            }

            Spacer()

            if canPick {
                Button("Elegir…", action: onPickMatch)
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .contextMenu {
            Button("Mostrar en el Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.currentURL])
            }
            if canPick {
                Button("Elegir coincidencia…", action: onPickMatch)
            }
            Divider()
            Button("Quitar de la lista", action: onRemove)
        }
    }

    private var canPick: Bool {
        switch item.status {
        case .needsSelection, .autoMatched, .noResults, .error: return true
        default: return false
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                .accessibilityLabel("Pendiente")
        case .searching:
            ProgressView().controlSize(.small)
        case .autoMatched:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                .accessibilityLabel("Listo para renombrar")
        case .needsSelection:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
                .accessibilityLabel("Requiere elegir coincidencia")
        case .noResults:
            Image(systemName: "exclamationmark.magnifyingglass").foregroundStyle(.orange)
                .accessibilityLabel("Sin resultados")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .accessibilityLabel("Error")
        case .renamed:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                .accessibilityLabel("Renombrado")
        case .renameFailed:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                .accessibilityLabel("Fallo al renombrar")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .noResults:
            Text("Sin coincidencias en TMDb").font(.caption).foregroundStyle(.orange)
        case .error(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .renameFailed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        case .renamed:
            Text("Renombrado").font(.caption).foregroundStyle(.blue)
        default:
            EmptyView()
        }
    }
}
