import SwiftUI

struct FileRowView: View {
    @ObservedObject var item: MediaItem
    var onPickMatch: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalURL.lastPathComponent)
                    .font(.system(.body, design: .default))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let proposed = item.proposedFilename {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(proposed)
                            .font(.system(.body, design: .default))
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                }

                statusLabel
            }

            Spacer()

            if item.status == .needsSelection || item.status == .autoMatched || item.status == .noResults {
                Button("Elegir…", action: onPickMatch)
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "circle.dashed").foregroundColor(.secondary)
        case .searching:
            ProgressView().controlSize(.small)
        case .autoMatched:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .needsSelection:
            Image(systemName: "questionmark.circle.fill").foregroundColor(.orange)
        case .noResults:
            Image(systemName: "exclamationmark.magnifyingglass").foregroundColor(.orange)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
        case .renamed:
            Image(systemName: "checkmark.seal.fill").foregroundColor(.blue)
        case .renameFailed:
            Image(systemName: "xmark.octagon.fill").foregroundColor(.red)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .noResults:
            Text("Sin coincidencias en TMDb").font(.caption).foregroundColor(.orange)
        case .error(let message):
            Text(message).font(.caption).foregroundColor(.red)
        case .renameFailed(let message):
            Text(message).font(.caption).foregroundColor(.red)
        case .renamed:
            Text("Renombrado").font(.caption).foregroundColor(.blue)
        default:
            EmptyView()
        }
    }
}
