import InstantTabCore
import SwiftUI

struct MonitorsPane: View {
    let model: SettingsModel
    @State private var editing: GroupDraft?

    var body: some View {
        PaneScroll { compact in
            PaneHeader(pane: .monitors, subtitle: "Choose which monitors Cmd+Tab lists apps from.")
            FileProblemBanner(configStore: model.configStore)
            arrangement(compact: compact)
            Group {
                scope
                groups
            }
            .disabled(model.configStore.fileIsBroken)
        }
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

    private func arrangement(compact: Bool) -> some View {
        VStack(spacing: 12) {
            DisplayArrangement(model: model)
                .frame(height: compact ? 170 : 210)
            StatusBar(
                title: "Cmd+Tab lists apps from \(currentTargetNames)",
                subtitle: compact ? nil : "Highlighted monitors are listed. The pointer marks the one under the mouse."
            ) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 18, height: 13)
            } trailing: {
                EmptyView()
            }
        }
        .padding(12)
        .background(Wallpaper())
        .clipShape(Hero.shape)
        .overlay(Hero.shape.strokeBorder(Card.stroke))
    }

    private var scope: some View {
        let selected = model.configStore.config.scope
        return SettingsCard(title: "Show apps from") {
            ForEach(Array(model.scopeOptions.enumerated()), id: \.element) { index, option in
                if index > 0 { RowDivider() }
                let groupExists = model.groups.contains { $0.name == option.groupName }
                ScopeRow(
                    title: option.title(groupExists: groupExists),
                    subtitle: option.explanation,
                    symbol: option.groupName == nil ? option.symbol : groupExists ? "circle.fill" : "exclamationmark.triangle",
                    tint: option.groupName.flatMap { groupExists ? model.color(ofGroup: $0) : nil },
                    isSelected: option == selected,
                    select: { model.binding(\.scope).wrappedValue = option }
                )
            }
        }
    }

    private var groups: some View {
        SettingsCard(
            title: "Monitor groups",
            footer: "A group combines monitors, for example every external one. It matches by kind, shape or position, so it keeps working when you swap monitors."
        ) {
            if model.groups.isEmpty {
                EmptyRow(text: "No groups yet.")
                RowDivider()
            } else {
                ForEach(model.groups, id: \.name) { group in
                    GroupRow(
                        group: group,
                        color: model.color(ofGroup: group.name),
                        members: memberNames(group),
                        edit: { editing = GroupDraft(group: group, originalName: group.name) },
                        delete: { model.deleteGroup(group.name) }
                    )
                    RowDivider()
                }
            }
            CardActions {
                Button {
                    editing = GroupDraft(group: DisplayGroup(name: model.newGroupName(), rules: []), originalName: nil)
                } label: {
                    Label("New Group…", systemImage: "plus")
                }
            }
        }
    }

    private var currentTargetNames: String {
        guard let targets = model.currentTargets else { return "all monitors" }
        return model.displayNames(targets, empty: "all monitors")
    }

    private func memberNames(_ group: DisplayGroup) -> String {
        model.displayNames(group.members(in: model.displays), empty: "No monitor connected")
    }
}

private struct ScopeRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            SettingsRow(title: title, subtitle: subtitle) {
                Image(systemName: symbol)
                    .font(.system(size: tint == nil ? 15 : 10, weight: .medium))
                    .foregroundStyle(tint ?? (isSelected ? Color.accentColor : Color.secondary))
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            Circle().fill(color).frame(width: 10, height: 10)
        } trailing: {
            HStack(spacing: 8) {
                Button("Edit…", action: edit)
                    .glassButton()
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

    /// Uuids compare case-insensitively, as the matcher does.
    private func sameRule(_ lhs: DisplayRule, _ rhs: DisplayRule) -> Bool {
        if case .uuid(let a) = lhs, case .uuid(let b) = rhs { return a.caseInsensitiveCompare(b) == .orderedSame }
        return lhs == rhs
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
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .mouseDisplay: "cursorarrow"
        case .focusedDisplay: "macwindow"
        case .mouseGroup: "cursorarrow.rays"
        case .group: "circle.fill"
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
        let specific = rules.filter { if case .uuid = $0 { true } else { false } }.count
        if specific > 0 { parts.append(specific == 1 ? "one specific monitor" : "\(specific) specific monitors") }
        return parts.formatted(.list(type: .or))
    }
}
