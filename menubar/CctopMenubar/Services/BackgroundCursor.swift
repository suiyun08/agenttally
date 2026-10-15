import Foundation

/// Lets cctop set the pointer while another app is frontmost. The panel never activates cctop,
/// and macOS otherwise ignores cursor changes from a background app. The switch is a private
/// CoreGraphics connection property looked up at runtime; if it is missing or refused, the
/// pointer simply keeps its shape and the edge grip still shows.
enum BackgroundCursor {
    static func enable() {
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        guard let handle = dlopen(nil, RTLD_NOW),
              let connectionSymbol = dlsym(handle, "_CGSDefaultConnection"),
              let setPropertySymbol = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connectionSymbol, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setPropertySymbol, to: SetConnectionProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}
