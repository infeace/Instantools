import InstantTabCore
import SwiftUI

struct ExclusionsPane: View {
    let model: SettingsModel
    @State private var addingBundleId = false
    @State private var bundleIdText = ""

    private var rules: [Config.Exclusion] { model.configStore.config.exclude }

    var body: some View {
        Form {
            FileProblemSection(configStore: model.configStore)
            Group {
                Section {
                    if rules.isEmpty {
                        Text("No excluded apps. Every running app shows up, like native Cmd+Tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rules, id: \.bundleId) { rule in
                            ExclusionRow(
                                rule: rule,
                                info: model.apps.info(for: rule.bundleId),
                                when: model.exclusionWhen(rule.bundleId),
                                remove: { model.removeExclusion(rule.bundleId) }
                            )
                        }
                    }
                } header: {
                    Text("Excluded apps")
                } footer: {
                    footer
                }
                if !model.altTabRulesToImport.isEmpty {
                    altTabImport
                }
            }
            .disabled(model.configStore.fileIsBroken)
        }
        .formStyle(.grouped)
        .navigationTitle("Excluded Apps")
    }

    private var footer: some View {
        HStack {
            Menu("Add Running App") {
                ForEach(model.runningAppsToExclude, id: \.bundleId) { app in
                    Button {
                        model.exclude(app.bundleId)
                    } label: {
                        if let icon = AppLookup.menuIcon(app.icon) {
                            Label { Text(app.name) } icon: { Image(nsImage: icon) }
                        } else {
                            Text(app.name)
                        }
                    }
                }
            }
            .fixedSize()
            .disabled(model.runningAppsToExclude.isEmpty)
            Button("Choose App…") { model.chooseAppsToExclude() }
            Button("Add by ID…") { addingBundleId = true }
                .popover(isPresented: $addingBundleId, arrowEdge: .bottom) { bundleIdPopover }
            Spacer()
        }
    }

    private var altTabImport: some View {
        let rules = model.altTabRulesToImport
        let names = rules.map { rule in
            let name = model.apps.info(for: rule.bundleId).name
            return rule.when == .noWindows ? "\(name) (when it has no windows)" : name
        }
        return Section {
            LabeledContent {
                Button("Import") { model.importAltTab() }
            } label: {
                Text("Import from AltTab")
                Text("AltTab hides \(names.formatted(.list(type: .and))). Your current rules stay as they are.")
            }
        }
    }

    private var bundleIdPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exclude by bundle ID")
                .font(.headline)
            TextField("com.example.App", text: $bundleIdText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addBundleId)
            Text("End with * to match every app whose ID starts with the text before it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { addingBundleId = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addBundleId)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedBundleId.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var trimmedBundleId: String {
        bundleIdText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addBundleId() {
        guard !trimmedBundleId.isEmpty else { return }
        model.exclude(trimmedBundleId)
        bundleIdText = ""
        addingBundleId = false
    }
}

private struct ExclusionRow: View {
    let rule: Config.Exclusion
    let info: AppLookup.Info
    let when: Binding<Config.Exclusion.When>
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = info.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: rule.bundleId.hasSuffix("*") ? "square.stack.3d.up" : "questionmark.app.dashed")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name)
                Text(info.isInstalled ? rule.bundleId : "\(rule.bundleId), not installed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Exclude", selection: when) {
                Text("Always").tag(Config.Exclusion.When.always)
                Text("When it has no windows").tag(Config.Exclusion.When.noWindows)
            }
            .labelsHidden()
            .fixedSize()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop excluding \(info.name)")
        }
    }
}
