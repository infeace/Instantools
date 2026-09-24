import InstantTabCore
import SwiftUI

struct MonitorsPane: View {
    let model: SettingsModel
    @State private var editing: GroupDraft?

    var body: some View {
        Form {
            Section {
                DisplayArrangement(model: model)
                    .frame(height: 210)
            } header: {
                Text("Your monitors")
            } footer: {
                Text("Highlighted monitors are the ones Cmd+Tab lists apps from right now. The pointer marks the monitor under the mouse.")
                    .foregroundStyle(.secondary)
            }

            Section("Show apps from") {
                Picker("Show apps from", selection: model.binding(\.scope)) {
                    ForEach(model.scopeOptions, id: \.self) { scope in
                        Text(scope.title(groupExists: model.groups.contains { $0.name == scope.groupName })).tag(scope)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                LabeledContent {
                    Text(currentTargetNames)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                } label: {
                    Text("Right now")
                    Text(model.configStore.config.scope.explanation)
                }
            }

            Section {
                if model.groups.isEmpty {
                    Text("No groups yet. A group combines monitors, for example every external one, and keeps working when you swap monitors because it matches by kind, shape or position.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.groups, id: \.name) { group in
                        GroupRow(
                            group: group,
                            color: model.color(ofGroup: group.name),
                            members: memberNames(group),
                            edit: { editing = GroupDraft(group: group, originalName: group.name) },
                            delete: { model.deleteGroup(group.name) }
                        )
                    }
                }
            } header: {
                Text("Monitor groups")
            } footer: {
                HStack {
                    Button("New Group…") {
                        editing = GroupDraft(group: DisplayGroup(name: model.newGroupName(), rules: []), originalName: nil)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Monitors")
        .sheet(item: $editing) { draft in
            GroupEditor(
                draft: draft,
                displays: model.displays,
                takenNames: Set(model.groups.map(\.name)).subtracting([draft.originalName].compactMap { $0 }),
                save: { group in model.saveGroup(group, replacing: draft.originalName) }
            )
        }
    }

    private var currentTargetNames: String {
        guard let targets = model.currentTargets else { return "All monitors" }
        let names = model.displays.filter { targets.contains($0.id) }.map(\.name)
        return names.isEmpty ? "All monitors" : names.formatted(.list(type: .and))
    }

    private func memberNames(_ group: DisplayGroup) -> String {
        let members = group.members(in: model.displays)
        let names = model.displays.filter { members.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No monitor connected" : names.formatted(.list(type: .and))
    }
}

// MARK: Arrangement

/// The connected monitors drawn to scale, as in System Settings > Displays.
private struct DisplayArrangement: View {
    let model: SettingsModel

    var body: some View {
        GeometryReader { geometry in
            let displays = model.displays
            let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            if displays.isEmpty || bounds.isNull {
                Text("No monitors found").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let scale = min((geometry.size.width - 16) / bounds.width, (geometry.size.height - 16) / bounds.height)
                let origin = CGPoint(
                    x: (geometry.size.width - bounds.width * scale) / 2,
                    y: (geometry.size.height - bounds.height * scale) / 2
                )
                let targets = model.currentTargets
                ZStack(alignment: .topLeading) {
                    ForEach(displays, id: \.id) { display in
                        let rect = CGRect(
                            x: origin.x + (display.frame.minX - bounds.minX) * scale,
                            y: origin.y + (display.frame.minY - bounds.minY) * scale,
                            width: display.frame.width * scale,
                            height: display.frame.height * scale
                        ).insetBy(dx: 3, dy: 3)
                        DisplayTile(
                            display: display,
                            inScope: targets?.contains(display.id) ?? true,
                            hasMouse: display.id == model.mouseDisplay,
                            groupColors: model.groupColors(of: display)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
    }
}

private struct DisplayTile: View {
    let display: Display
    let inScope: Bool
    let hasMouse: Bool
    let groupColors: [Color]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(inScope ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08))
            .overlay(shape.strokeBorder(inScope ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: inScope ? 2 : 1))
            .overlay {
                VStack(spacing: 2) {
                    Text(display.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(verbatim: "\(Int(display.frame.width)) × \(Int(display.frame.height))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        if display.isMain { Badge("Main") }
                        if display.isBuiltIn { Badge("Built-in") }
                    }
                }
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(Array(groupColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                }
                .padding(7)
            }
            .overlay(alignment: .topTrailing) {
                if hasMouse {
                    Image(systemName: "cursorarrow")
                        .font(.caption)
                        .padding(6)
                }
            }
            .help(display.name)
    }
}

private struct Badge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.18)))
    }
}

// MARK: Groups

private struct GroupRow: View {
    let group: DisplayGroup
    let color: Color
    let members: String
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                Text(group.rules.isEmpty ? "No rules yet" : "Matches \(group.rules.map(\.title).formatted(.list(type: .or)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Now: \(members)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit…", action: edit)
            Button(action: delete) {
                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete \(group.name)")
        }
    }
}

struct GroupDraft: Identifiable {
    let id = UUID()
    var group: DisplayGroup
    var originalName: String?
}

struct GroupEditor: View {
    let displays: [Display]
    let takenNames: Set<String>
    let save: (DisplayGroup) -> Void
    @State private var group: DisplayGroup
    @State private var namePatterns: String
    @Environment(\.dismiss) private var dismiss

    init(draft: GroupDraft, displays: [Display], takenNames: Set<String>, save: @escaping (DisplayGroup) -> Void) {
        self.displays = displays
        self.takenNames = takenNames
        self.save = save
        _group = State(initialValue: draft.group)
        _namePatterns = State(initialValue: draft.group.rules.compactMap { rule in
            if case .name(let pattern) = rule { pattern } else { nil }
        }.joined(separator: ", "))
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $group.name)
                    LabeledContent("Matches now") {
                        Text(matchesNow)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    if let problem = nameProblem {
                        Text(problem).foregroundStyle(.red)
                    }
                }
                Section {
                    LabeledContent("Kind") {
                        HStack(spacing: 18) {
                            check("Built-in", .builtIn)
                            check("External", .external)
                        }
                    }
                    LabeledContent("Shape") {
                        HStack(spacing: 18) {
                            check("Landscape", .landscape)
                            check("Portrait", .portrait)
                        }
                    }
                    LabeledContent("Position") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                            GridRow {
                                check("Main", .main)
                                check("Leftmost", .leftmost)
                                check("Rightmost", .rightmost)
                            }
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                check("Topmost", .topmost)
                                check("Bottommost", .bottommost)
                            }
                        }
                    }
                    LabeledContent("Name") {
                        TextField("Name matches", text: $namePatterns, prompt: Text("DELL*, LG*"))
                            .labelsHidden()
                            .frame(maxWidth: 200)
                    }
                } header: {
                    Text("A monitor is in this group when it matches any of")
                } footer: {
                    Text("Main is the display with the menu bar. Names take wildcards * and ?, separated by commas.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(displays, id: \.id) { display in
                        check(display.name, .uuid(display.uuid))
                    }
                    ForEach(disconnectedUUIDs, id: \.self) { uuid in
                        Toggle(isOn: rule(.uuid(uuid))) {
                            Text("Disconnected monitor")
                            Text(uuid)
                        }
                        .toggleStyle(.checkbox)
                    }
                } header: {
                    Text("Or is one of these exact monitors")
                } footer: {
                    Text("Identical monitors can swap identities, so prefer the rules above when you can.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(finished)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(nameProblem != nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    private var trimmedName: String { group.name.trimmingCharacters(in: .whitespaces) }

    private var nameProblem: String? {
        if trimmedName.isEmpty { return "A group needs a name." }
        if takenNames.contains(trimmedName) { return "Another group already has this name." }
        return nil
    }

    /// The rules in a stable order: descriptions first, then specific monitors, then names.
    private var finished: DisplayGroup {
        let patterns = namePatterns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let keywords = DisplayRule.keywords.filter(group.rules.contains)
        let uuids = group.rules.filter { if case .uuid = $0 { true } else { false } }
        return DisplayGroup(name: trimmedName, rules: keywords + uuids + patterns.map(DisplayRule.name))
    }

    private var matchesNow: String {
        let members = finished.members(in: displays)
        let names = displays.filter { members.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No connected monitor" : names.formatted(.list(type: .and))
    }

    private var disconnectedUUIDs: [String] {
        let connected = Set(displays.map { $0.uuid.lowercased() })
        return group.rules.compactMap { rule in
            if case .uuid(let uuid) = rule, !connected.contains(uuid.lowercased()) { uuid } else { nil }
        }
    }

    private func check(_ title: String, _ rule: DisplayRule) -> some View {
        Toggle(title, isOn: self.rule(rule)).toggleStyle(.checkbox)
    }

    private func rule(_ rule: DisplayRule) -> Binding<Bool> {
        Binding(
            get: { group.rules.contains(rule) },
            set: { on in
                if on {
                    if !group.rules.contains(rule) { group.rules.append(rule) }
                } else {
                    group.rules.removeAll { $0 == rule }
                }
            }
        )
    }
}

// MARK: Labels

extension Config.Scope {
    var groupName: String? {
        if case .group(let name) = self { name } else { nil }
    }

    func title(groupExists: Bool) -> String {
        switch self {
        case .all: "All monitors"
        case .mouseDisplay: "The monitor under the mouse"
        case .focusedDisplay: "The monitor with the focused window"
        case .mouseGroup: "The group the mouse is in"
        case .group(let name): groupExists ? "Group: \(name)" : "Group: \(name) (deleted)"
        }
    }

    var explanation: String {
        switch self {
        case .all: "Every running app, like native Cmd+Tab."
        case .mouseDisplay: "Apps with a window on the monitor under the mouse."
        case .focusedDisplay: "Apps with a window on the monitor you are working on."
        case .mouseGroup: "Apps on every monitor of the first group that contains the monitor under the mouse. Outside any group, just that monitor."
        case .group(let name): "Apps on the monitors in \(name), wherever the mouse is."
        }
    }
}

extension DisplayRule {
    var title: String {
        switch self {
        case .builtIn: "built-in"
        case .external: "external"
        case .landscape: "landscape"
        case .portrait: "portrait"
        case .main: "main"
        case .leftmost: "leftmost"
        case .rightmost: "rightmost"
        case .topmost: "topmost"
        case .bottommost: "bottommost"
        case .name(let pattern): "named \(pattern)"
        case .uuid: "one specific monitor"
        }
    }
}
