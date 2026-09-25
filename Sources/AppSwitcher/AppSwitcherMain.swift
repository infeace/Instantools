import InstantoolsCore
import InstantoolsKit

@main
struct AppSwitcherMain {
    @MainActor static func main() {
        ToolRuntime.run(.appSwitcher) { AppSwitcherDelegate() }
    }
}
