import SwiftUI

struct SettingsView: View {
    @AppStorage("tmdbAPIKey") private var apiKey: String = ""

    var body: some View {
        Form {
            Section {
                SecureField("API Key de TMDb", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Link("Consigue una API key gratuita en themoviedb.org",
                     destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    .font(.caption)
            } header: {
                Text("TMDb")
            } footer: {
                Text("La app usa TMDb (The Movie Database) para buscar metadatos de películas y series. Necesitas una cuenta gratuita y una API key v3.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 420, height: 180)
    }
}
