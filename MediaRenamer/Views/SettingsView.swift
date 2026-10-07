import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                SecureField("API key o token de TMDb", text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)
                Link("Consigue una API key gratuita en themoviedb.org",
                     destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    .font(.caption)
            } header: {
                Text("TMDb")
            } footer: {
                Text("Vale la API key v3 o el «API Read Access Token» v4 (recomendado: no viaja en la URL). Se guarda en el Llavero de macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Idioma de los títulos", selection: $settings.language) {
                    ForEach(AppSettings.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
            }

            Section {
                Text("Este producto usa la API de TMDb pero no está avalado ni certificado por TMDb.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 460, height: 300)
    }
}
