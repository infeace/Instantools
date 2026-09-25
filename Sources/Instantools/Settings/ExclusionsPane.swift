import AppSwitcherCore
import SwiftUI

struct ExclusionsPane: View {
    let model: SettingsModel
    @State private var addingBundleId = false
    @State private var bundleIdText = ""

    private var rules: [Config.Exclusion] { model.configStore.config.exclude }
    private var passThrough: [String] { model.configStore.config.passThrough }

    var body: some View {
        PaneScroll { _ in
            PaneHeader(pane: .exclusions, subtitle: "Apps Cmd+Tab leaves out, and apps that get Cmd+Tab for themselves.")
            FileProblemBanner(configStore: model.configStore)
            Group {
                if !model.altTabRulesToImport.isEmpty { altTabImport }
                SettingsCard(
                    title: "Excluded apps",
                    footer: "\"When it has no windows\" leaves an app out only while none of its windows are open, which suits apps like Finder."
                ) {
                    if rules.isEmpty { EmptyRow(text: "No excluded apps yet.") }
                    DividedRows(rules, id: \.bundleId) { rule in
                        ExclusionRow(
                            rule: rule,
                            info: model.apps.info(for: rule.bundleId),
                            when: model.exclusionWhen(rule.bundleId),
                            remove: { model.removeExclusion(rule.bundleId) }
                        )
                    }
                    CardActions { addButtons }
                }
                passThroughCard
            }
            .disabled(model.configStore.fileIsBroken)
        }
    }

    @ViewBuilder private var addButtons: some View {
        RunningAppMenu(apps: model.runningAppsToExclude, add: model.exclude)
        Button("Choose Apps…") { model.chooseAppsToExclude() }
        Button("Add by ID…") { addingBundleId = true }
            .popover(isPresented: $addingBundleId, arrowEdge: .bottom) { bundleIdPopover }
    }

    private var passThroughCard: some View {
        SettingsCard(
            title: "Apps that keep Cmd+Tab",
            footer: "While one of these apps is in front, Cmd+Tab goes to it instead of InstantTab. For virtual machines, remote desktops and games. Click another app to leave it."
        ) {
            if passThrough.isEmpty { EmptyRow(text: "None yet.") }
            DividedRows(passThrough, id: \.self) { bundleId in
                let info = model.apps.info(for: bundleId)
                SettingsRow(title: info.name, subtitle: info.subtitle(bundleId: bundleId)) {
                    AppIcon(info: info, isPattern: bundleId.hasSuffix("*"))
                } trailing: {
                    RemoveButton(help: "Take Cmd+Tab back from \(info.name)") { model.removePassThrough(bundleId) }
                }
            }
            CardActions {
                RunningAppMenu(apps: model.runningAppsToPassThrough) { model.addPassThrough([$0]) }
                Button("Choose Apps…") { model.chooseAppsToPassThrough() }
            }
        }
    }

    private var altTabImport: some View {
        let names = model.altTabRulesToImport.map { rule in
            let name = model.apps.info(for: rule.bundleId).name
            return rule.when == .noWindows ? "\(name) (when it has no windows)" : name
        }
        return Callout(
            symbol: "square.and.arrow.down.fill",
            colors: Tile.monitors.colors,
            title: "Import from AltTab",
            message: "AltTab hides \(names.formatted(.list(type: .and))). Your current rules stay as they are.",
            action: "Import",
            perform: model.importAltTab
        )
    }

    private var bundleIdPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exclude by bundle ID")
                .font(.headline)
            TextField("com.example.App", text: $bundleIdText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addBundleId)
            Text(bundleIdProblem ?? "End with * to match every app whose ID starts with the text before it.")
                .font(.caption)
                .foregroundStyle(bundleIdProblem == nil ? .secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { addingBundleId = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addBundleId)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedBundleId.isEmpty || bundleIdProblem != nil)
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var trimmedBundleId: String {
        bundleIdText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bundleIdProblem: String? {
        if trimmedBundleId == "*" { return "A lone * would hide every app." }
        if model.configStore.config.excludes(trimmedBundleId) { return "This app is already excluded." }
        return nil
    }

    private func addBundleId() {
        guard !trimmedBundleId.isEmpty, bundleIdProblem == nil else { return }
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
        SettingsRow(title: info.name, subtitle: info.subtitle(bundleId: rule.bundleId)) {
            AppIcon(info: info, isPattern: rule.bundleId.hasSuffix("*"))
        } trailing: {
            HStack(spacing: 8) {
                Picker("Exclude \(info.name)", selection: when) {
                    Text("Always").tag(Config.Exclusion.When.always)
                    Text("When it has no windows").tag(Config.Exclusion.When.noWindows)
                }
                .labelsHidden()
                .fixedSize()
                RemoveButton(help: "Stop excluding \(info.name)", action: remove)
            }
        }
    }
}
