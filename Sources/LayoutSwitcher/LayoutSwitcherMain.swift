import InstantoolsCore
import InstantoolsKit

@main
struct LayoutSwitcherMain {
    @MainActor static func main() {
        ToolRuntime.run(.layoutSwitcher) { LayoutSwitcherDelegate() }
    }
}
