import SwiftUI

extension LocalModelsPage {
    var modelsSection: some View {
        SectionCard(title: "Models") {
            VStack(alignment: .leading, spacing: 14) {
                if service.installedModels.isEmpty {
                    Text("No models yet. Pull one below.")
                        .font(BodyFont.system(size: 12))
                        .foregroundColor(Palette.textSecondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(service.installedModels) { model in
                            modelRow(model)
                        }
                    }
                }

                Divider().background(Color.white.opacity(0.07))
                pullRow

                if !service.downloads.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(service.downloads.values), id: \.model) { download in
                            downloadRow(download)
                        }
                    }
                }
            }
        }
    }

    func modelRow(_ model: LocalModelsClient.ModelTag) -> some View {
        let isLoaded = service.loadedModels.contains { $0.name == model.name }
        let isDefault = service.defaultModel == model.name
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(BodyFont.system(size: 12.5, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    if isDefault { badge("Default") }
                    if isLoaded { badge("In memory") }
                }
                Text(humanSize(model.size))
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            if !isDefault {
                Button("Use") { service.setDefault(model: model.name) }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
            }
            if isLoaded {
                Button("Unload") { Task { await service.unload(model: model.name) } }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5))
            }
            Button {
                Task { await service.delete(model: model.name) }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
            }
            .buttonStyle(.borderless)
        }
    }

    var pullRow: some View {
        HStack(spacing: 8) {
            TextField("model:tag (e.g. llama3.2:1b)", text: $pullField)
                .textFieldStyle(.roundedBorder)
                .font(BodyFont.system(size: 12))
            Button("Download") {
                let name = pullField.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                pullField = ""
                Task { await service.pull(model: name) }
            }
            .disabled(pullField.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func downloadRow(_ download: LocalModelsService.Download) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(download.model)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                if case .failed = download.state {
                    Button("Dismiss") { service.dismissDownloadError(for: download.model) }
                        .buttonStyle(.borderless)
                        .font(BodyFont.system(size: 11))
                }
            }
            switch download.state {
            case .running(let progress, let status):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(status)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary)
            case .failed(let message):
                Text(message)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                    .lineLimit(3)
            }
        }
    }
}
