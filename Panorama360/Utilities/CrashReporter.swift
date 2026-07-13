import Foundation

/// Captures uncaught Objective-C exceptions (the kind AVFoundation and most iOS
/// framework crashes raise) and persists the reason + stack to Documents so it
/// can be shown on the next launch.
///
/// This is the diagnostic bridge for a sideloaded app built from Windows: there
/// is no Mac console attached, so the app carries its own "what just crashed?"
/// note. It catches `NSException`-style crashes (the common case for camera/
/// Metal/runtime-config errors). For `EXC_BAD_ACCESS` signal crashes it will not
/// fire — for those, read the `.ips` crash log on the device.
public enum CrashReporter {

    fileprivate static let fileName = "last_crash.txt"

    /// Installs the handler. Call once at app launch (before any camera work).
    public static func install() {
        // Must be a C function pointer — Swift closures that capture context are rejected.
        NSSetUncaughtExceptionHandler(panorama360UncaughtExceptionHandler)
    }

    /// The persisted crash text from the previous launch, if any.
    public static func lastCrash() -> String? {
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent(fileName)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Deletes the persisted report (call after the user has read/copied it).
    public static func clear() {
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: docs.appendingPathComponent(fileName))
    }
}

/// Top-level `@convention(c)`-compatible handler (no captures).
private func panorama360UncaughtExceptionHandler(_ exception: NSException) {
    guard let docs = FileManager.default.urls(for: .documentDirectory,
                                               in: .userDomainMask).first else { return }
    let url = docs.appendingPathComponent(CrashReporter.fileName)
    let stack = exception.callStackSymbols.joined(separator: "\n")
    let report = """
    Panorama360 crash report
    ========================
    Name:   \(exception.name.rawValue)
    Reason: \(exception.reason ?? "(none)")

    Call stack:
    \(stack)
    """
    try? report.write(to: url, atomically: true, encoding: .utf8)
}
