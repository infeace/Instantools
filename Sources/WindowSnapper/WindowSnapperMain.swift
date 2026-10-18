import InstantoolsCore
import InstantoolsKit

@main
struct WindowSnapperMain {
    @MainActor static func main() {
        ToolRuntime.run(.windowSnapper) { WindowSnapperDelegate() }
    }
}
