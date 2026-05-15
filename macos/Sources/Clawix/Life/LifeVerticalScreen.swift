import SwiftUI

/// Router shim that picks between the generic 3-pane explorer and any
/// per-vertical override. Override screens live as separate files
/// (`WorkoutsLifeScreen`, `NutritionLifeScreen`, etc.); until they ship
/// every vertical falls back to `GenericVerticalScreen`.
struct LifeVerticalScreen: View {
    let verticalId: String

    var body: some View {
        switch verticalId {
        case "journal":
            JournalLifeScreen(verticalId: verticalId)
        case "finance":
            FinanceLifeScreen(verticalId: verticalId)
        case "workouts":
            WorkoutsLifeScreen(verticalId: verticalId)
        default:
            GenericVerticalScreen(verticalId: verticalId)
        }
    }
}

/// 3-pane explorer that drives most verticals: catalog on the left,
/// observations in the middle, detail + add form on the right. Modeled
/// after `MemoryHomeView` with the same paddings and palettes.
struct GenericVerticalScreen: View {
    let verticalId: String

    @StateObject private var manager = LifeManager.shared
    @State private var selectedVariableId: String?
    @State private var newValueText: String = ""
    @State private var newNotesText: String = ""
    @State private var search: String = ""

    private var entry: LifeRegistryEntry? { LifeRegistry.entry(byId: verticalId) }
    private var state: LifeVerticalState { manager.state(for: verticalId) }

    var body: some View {
        HStack(spacing: 0) {
            catalogPane
                .frame(width: 240)
            Divider().background(Color.white.opacity(0.06))
            observationsPane
                .frame(maxWidth: .infinity)
            Divider().background(Color.white.opacity(0.06))
            detailPane
                .frame(width: 320)
        }
        .background(Palette.background)
        .task {
            await refresh()
        }
        .onChange(of: verticalId) { _, _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        await manager.reloadCatalog(for: verticalId)
        if selectedVariableId == nil {
            selectedVariableId = state.catalog.first?.id
        }
        await manager.reloadObservations(for: verticalId, variableId: selectedVariableId)
    }

    // MARK: - Panes

    private var catalogPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(entry?.label ?? verticalId.capitalized)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredCatalog) { variable in
                        Button(action: { select(variable.id) }) {
                            HStack(spacing: 6) {
                                Text(variable.label)
                                    .font(.system(size: 13))
                                    .foregroundColor(
                                        variable.id == selectedVariableId
                                            ? Palette.textPrimary
                                            : Palette.textSecondary
                                    )
                                Spacer()
                                if variable.origin == .user {
                                    Text("U")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(Color.white.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                variable.id == selectedVariableId
                                    ? Color.white.opacity(0.05)
                                    : Color.clear
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
            .thinScrollers()
        }
    }

    private var observationsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(observationsTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if state.observations.isEmpty {
                VStack(spacing: 6) {
                    Text("No observations yet")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.textSecondary)
                    Text("Use the right panel to add the first one.")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(state.observations) { observation in
                            observationRow(observation)
                            Divider().background(Color.white.opacity(0.04))
                        }
                    }
                }
                .thinScrollers()
            }
        }
    }

    private func observationRow(_ observation: LifeObservation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(formatTimestamp(observation.recordedAt))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(observation.value.displayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Palette.textPrimary)
                if let notes = observation.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            Spacer()
            Button(action: {
                Task {
                    await manager.deleteObservation(
                        verticalId: verticalId,
                        observationId: observation.id
                    )
                }
            }) {
                Text("Delete")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let variableId = selectedVariableId,
               let variable = state.catalog.first(where: { $0.id == variableId }) {
                Text("Add observation")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(variable.label)
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                valueField(for: variable)
                TextField("Notes (optional)", text: $newNotesText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(3, reservesSpace: true)
                    .font(.system(size: 12))
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                Button(action: {
                    Task { await submit(variable) }
                }) {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                Text("Select a variable")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func valueField(for variable: LifeCatalogEntry) -> some View {
        switch variable.valueType {
        case .text, .enum:
            TextField("Value", text: $newValueText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        case .boolean:
            Toggle(isOn: Binding(
                get: { newValueText == "true" },
                set: { newValueText = $0 ? "true" : "false" }
            )) {
                Text("Yes / No").font(.system(size: 12))
                    .foregroundColor(Palette.textSecondary)
            }
            .toggleStyle(.switch)
        default:
            TextField(variable.unit.label, text: $newValueText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        }
    }

    // MARK: - Helpers

    private var filteredCatalog: [LifeCatalogEntry] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return state.catalog }
        return state.catalog.filter { $0.label.lowercased().contains(trimmed) }
    }

    private var observationsTitle: String {
        guard let variableId = selectedVariableId,
              let variable = state.catalog.first(where: { $0.id == variableId }) else {
            return "Observations"
        }
        return variable.label
    }

    private func select(_ variableId: String) {
        selectedVariableId = variableId
        Task {
            await manager.reloadObservations(for: verticalId, variableId: variableId)
        }
    }

    private func submit(_ variable: LifeCatalogEntry) async {
        let trimmed = newValueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: LifeObservationValue
        switch variable.valueType {
        case .boolean:
            value = .bool(trimmed == "true")
        case .text, .enum:
            value = .text(trimmed)
        default:
            if let parsed = Double(trimmed) {
                value = .number(parsed)
            } else {
                value = .text(trimmed)
            }
        }
        let input = LifeUpsertObservationInput(
            id: nil,
            variableId: variable.id,
            value: value,
            unitId: variable.unit.id,
            recordedAt: Date().timeIntervalSince1970 * 1000,
            source: .manual,
            notes: newNotesText.isEmpty ? nil : newNotesText,
            sessionId: nil,
            externalId: nil
        )
        await manager.upsertObservation(verticalId: verticalId, input: input)
        newValueText = ""
        newNotesText = ""
    }

    private func formatTimestamp(_ epochMs: Double) -> String {
        let date = Date(timeIntervalSince1970: epochMs / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Specialized entry points backed by the generic vertical surface

struct JournalLifeScreen: View {
    let verticalId: String
    var body: some View {
        GenericVerticalScreen(verticalId: verticalId)
    }
}

struct FinanceLifeScreen: View {
    let verticalId: String
    var body: some View {
        GenericVerticalScreen(verticalId: verticalId)
    }
}

struct WorkoutsLifeScreen: View {
    let verticalId: String
    var body: some View {
        GenericVerticalScreen(verticalId: verticalId)
    }
}
