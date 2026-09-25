import AppSwitcherCore
import SwiftUI

struct MonitorsPane: View {
    let model: SettingsModel
    @State private var editing: GroupDraft?

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .monitors, subtitle: "Choose which monitors Cmd+Tab lists apps from.")
            FileProblemBanner(configStore: model.configStore)
            Hero {
                DisplayArrangement(model: model)
            } bar: {
                StatusBar(
                    title: "Cmd+Tab lists apps from \(currentTargetNames)",
                    subtitle: compact ? nil : "Highlighted monitors are listed. The pointer marks the one under the mouse."
                ) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                        .frame(width: 18, height: 13)
                }
            }
            Group {
                scope
                groups
            }
            .disabled(model.configStore.fileIsBroken)
        }
        .sheet(item: $editing) { draft in
            GroupEditor(
                draft: draft,
                displays: model.displays,
                takenNames: Set(model.groups.map(\.name)).subtracting([draft.originalName].compactMap { $0 }),
                canSave: !model.configStore.fileIsBroken,
                save: { group in model.saveGroup(group, replacing: draft.originalName) }
            )
        }
    }

    private var scope: some View {
        let selection = model.binding(\.scope)
        return SettingsCard(title: "Show apps from") {
            VStack(spacing: 0) {
                ForEach(Array(model.scopeOptions.enumerated()), id: \.element) { index, option in
                    if index > 0 { RowDivider(indented: true) }
                    let color = option.groupName.flatMap { name in model.groups.contains { $0.name == name } ? model.color(ofGroup: name) : nil }
                    ScopeRow(
                        option: option,
                        groupColor: color,
                        isSelected: option == selection.wrappedValue,
                        select: { selection.wrappedValue = option }
                    )
                }
            }
            // VoiceOver reads the rows as one radio group, as it did the old picker.
            .accessibilityRepresentation {
                Picker("Show apps from", selection: selection) {
                    ForEach(model.scopeOptions, id: \.self) { option in
                        Text(option.title(groupExists: model.groups.contains { $0.name == option.groupName })).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
    }

    private var groups: some View {
        SettingsCard(
            title: "Monitor groups",
            footer: "A group combines monitors, for example every external one. It matches by kind, shape or position, so it keeps working when you swap monitors."
        ) {
            if model.groups.isEmpty { EmptyRow(text: "No groups yet.") }
            ForEach(Array(model.groups.enumerated()), id: \.element.name) { index, group in
                if index > 0 { RowDivider(indented: true) }
                GroupRow(
                    group: group,
                    color: model.color(ofGroup: group.name),
                    members: model.displays.names(of: model.members(of: group)),
                    edit: { editing = GroupDraft(group: group, originalName: group.name) },
                    delete: { model.deleteGroup(group.name) }
                )
            }
            CardActions {
                Button("New Group…") {
                    editing = GroupDraft(group: DisplayGroup(name: model.newGroupName(), rules: []), originalName: nil)
                }
            }
        }
    }

    private var currentTargetNames: String {
        guard let targets = model.currentTargets else { return "all monitors" }
        return model.displays.names(of: targets)
    }
}

private struct ScopeRow: View {
    let option: Config.Scope
    /// Nil for the built-in scopes and for a group that no longer exists.
    let groupColor: Color?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let groupExists = option.groupName == nil || groupColor != nil
        Button(action: select) {
            SettingsRow(title: option.title(groupExists: groupExists), subtitle: option.explanation(groupExists: groupExists)) {
                if let groupColor {
                    GroupDot(color: groupColor)
                } else {
                    Image(systemName: option.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(!groupExists ? Color.orange : isSelected ? Color.accentColor : Color.secondary)
                }
            } trailing: {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
            }
            // A checkmark never needs its own line.
            .environment(\.compactLayout, false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let dark = colorScheme == .dark
        shape
            .fill(inScope ? Color.accentColor.opacity(dark ? 0.35 : 0.3) : Color.black.opacity(dark ? 0.3 : 0.12))
            .background(shape.fill(.regularMaterial))
            .overlay(shape.strokeBorder(inScope ? Color.accentColor : Color.white.opacity(dark ? 0.2 : 0.5), lineWidth: inScope ? 2 : 1))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
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
                .opacity(inScope ? 1 : 0.7)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    ForEach(Array(groupColors.enumerated()), id: \.offset) { _, color in
                        GroupDot(color: color, size: 8)
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

private struct GroupRow: View {
    let group: DisplayGroup
    let color: Color
    let members: String
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        SettingsRow(
            title: group.name,
            subtitle: "\(group.rules.isEmpty ? "No rules yet" : "Matches \(DisplayRule.summary(of: group.rules))")\nNow: \(members)"
        ) {
            GroupDot(color: color)
        } trailing: {
            HStack(spacing: 8) {
                Button("Edit…", action: edit)
                    .glassButton()
                    .accessibilityLabel("Edit \(group.name)")
                RemoveButton(help: "Delete \(group.name)", action: delete)
            }
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
    let canSave: Bool
    let save: (DisplayGroup) -> Void
    @State private var group: DisplayGroup
    @State private var namePatterns: String
    @Environment(\.dismiss) private var dismiss

    init(draft: GroupDraft, displays: [Display], takenNames: Set<String>, canSave: Bool, save: @escaping (DisplayGroup) -> Void) {
        self.displays = displays
        self.takenNames = takenNames
        self.canSave = canSave
        self.save = save
        _group = State(initialValue: draft.group)
        _namePatterns = State(initialValue: draft.group.rules.compactMap(\.pattern).joined(separator: ", "))
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
                    if let problem = saveProblem {
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
                    LabeledContent("Name matches") {
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
                    ForEach(displays.filter { !$0.uuid.isEmpty }, id: \.id) { display in
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
                .disabled(saveProblem != nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 620)
    }

    private var trimmedName: String { group.name.trimmingCharacters(in: .whitespaces) }

    private var saveProblem: String? {
        if !canSave { return "The settings file has an error, so changes cannot be saved until it is fixed." }
        if trimmedName.isEmpty { return "A group needs a name." }
        if takenNames.contains(trimmedName) { return "Another group already has this name." }
        return nil
    }

    private var finished: DisplayGroup {
        let patterns = namePatterns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let keywords = DisplayRule.keywords.filter(group.rules.contains)
        let uuids = group.rules.filter { $0.uuid != nil }
        return DisplayGroup(name: trimmedName, rules: keywords + uuids + patterns.map(DisplayRule.name))
    }

    private var matchesNow: String {
        displays.names(of: finished.members(in: displays))
    }

    /// Uuids compare case-insensitively, as the matcher does.
    private func sameRule(_ lhs: DisplayRule, _ rhs: DisplayRule) -> Bool {
        if case .uuid(let a) = lhs, case .uuid(let b) = rhs { return a.caseInsensitiveCompare(b) == .orderedSame }
        return lhs == rhs
    }

    private var disconnectedUUIDs: [String] {
        let connected = Set(displays.map { $0.uuid.lowercased() })
        return group.rules.compactMap(\.uuid).filter { !connected.contains($0.lowercased()) }
    }

    private func check(_ title: String, _ rule: DisplayRule) -> some View {
        Toggle(title, isOn: self.rule(rule)).toggleStyle(.checkbox)
    }

    private func rule(_ rule: DisplayRule) -> Binding<Bool> {
        Binding(
            get: { group.rules.contains { sameRule($0, rule) } },
            set: { on in
                if on {
                    if !group.rules.contains(where: { sameRule($0, rule) }) { group.rules.append(rule) }
                } else {
                    group.rules.removeAll { sameRule($0, rule) }
                }
            }
        )
    }
}

extension Config.Scope {
    /// A group that exists shows its color instead, so `.group` only draws for a missing one.
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .mouseDisplay: "cursorarrow"
        case .focusedDisplay: "macwindow"
        case .mouseGroup: "cursorarrow.rays"
        case .group: "exclamationmark.triangle"
        }
    }

    var groupName: String? {
        if case .group(let name) = self { name } else { nil }
    }

    func title(groupExists: Bool) -> String {
        switch self {
        case .all: "All monitors"
        case .mouseDisplay: "The monitor under the mouse"
        case .focusedDisplay: "The monitor with the focused window"
        case .mouseGroup: "The group the mouse is in"
        case .group(let name): groupExists ? "Group: \(name)" : "Group: \(name) (missing)"
        }
    }

    func explanation(groupExists: Bool) -> String {
        switch self {
        case .all: "Every running app, like native Cmd+Tab."
        case .mouseDisplay: "Apps with a window on the monitor under the mouse."
        case .focusedDisplay: "Apps with a window on the monitor you are working on."
        case .mouseGroup: "Apps on every monitor of the first group that contains the monitor under the mouse. Outside any group, just that monitor."
        case .group(let name):
            groupExists ? "Apps on the monitors in \(name), wherever the mouse is." : "No group has this name, so apps from every monitor are listed."
        }
    }
}

extension DisplayRule {
    static func summary(of rules: [DisplayRule]) -> String {
        var parts: [String] = rules.compactMap { rule in
            switch rule {
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
            case .uuid: nil
            }
        }
        let specific = rules.filter { $0.uuid != nil }.count
        if specific > 0 { parts.append(specific == 1 ? "one specific monitor" : "\(specific) specific monitors") }
        return parts.formatted(.list(type: .or))
    }

    var uuid: String? {
        if case .uuid(let uuid) = self { uuid } else { nil }
    }

    var pattern: String? {
        if case .name(let pattern) = self { pattern } else { nil }
    }
}
