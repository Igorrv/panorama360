import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Captures crash reasons and persists them to Documents so the next launch can
/// show *why* the app died. There is no Mac console when sideloading from
/// Windows, so the app carries its own "what just crashed?" note.
///
/// Two layers:
/// 1. `NSSetUncaughtExceptionHandler` — catches ObjC `NSException`s (most
///    AVFoundation / UIKit / camera-config crashes). The runtime is still
///    functional, so we write the full call stack via Foundation.
/// 2. `signal()` trap — catches fatal signals (`SIGABRT`, `SIGSEGV`, …) that
///    the exception handler misses (bad-memory-access crashes). Best-effort:
///    the handler uses only async-signal-safe calls — a fixed `StaticString`
///    written to a pre-opened fd via the raw `write` syscall (no Foundation,
///    no allocation) — then re-raises so iOS still records the `.ips` log.
public enum CrashReporter {

    fileprivate static let fileName = "last_crash.txt"

    /// File descriptor kept open for the app's lifetime so the signal handler
    /// can write a breadcrumb using only the `write` syscall.
    fileprivate static var crashFD: CInt = -1

    /// Fixed message written by the signal handler. A `StaticString` lives in
    /// static storage — no heap allocation — so it is safe inside a signal
    /// handler. No runtime formatting (the signal number isn't worth the
    /// allocation risk); the device `.ips` log has the full detail.
    fileprivate static let signalMessage: StaticString = """
Panorama360 crash report
========================
Kind:   fatal signal (low-level crash — bad memory access or abort)
Reason: The app hit a signal it cannot recover from.
        Open Settings > Privacy & Security > Analytics & Improvements >
        Analytics Data > "Panorama360" and share the .ips file for the stack.
"""

    /// Installs both layers. Call once at app launch (before any camera work).
    public static func install() {
        openCrashFile()
        // Must be a C function pointer — Swift closures that capture context are rejected.
        NSSetUncaughtExceptionHandler(panorama360UncaughtExceptionHandler)
        installSignalHandlers()
    }

    private static func openCrashFile() {
        guard let docs = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first else { return }
        let url = docs.appendingPathComponent(fileName)
        // Create/truncate now and keep the fd open for the lifetime of the app.
        let fd = url.path.withCString { p in
            open(p, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
        if fd >= 0 { crashFD = fd }
    }

    // MARK: - Signal trap

    private static let handledSignals: [Int32] = [
        SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP, SIGSYS, SIGPIPE
    ]

    private static func installSignalHandlers() {
        // A non-capturing closure converts to a C function pointer. It performs
        // only async-signal-safe work (write/fsync/signal/raise + reads of
        // static storage) — no Foundation, no Swift String allocation.
        let handler: @convention(c) (Int32) -> Void = { sig in
            let fd = CrashReporter.crashFD
            if fd >= 0 {
                let msg = CrashReporter.signalMessage
                if msg.hasPointerRepresentation {
                    let base = UnsafeRawPointer(msg.utf8Start)
                    var remaining = Int(msg.utf8CodeUnitCount)
                    var ptr = base
                    while remaining > 0 {
                        let written = write(fd, ptr, remaining)
                        if written <= 0 { break }
                        ptr = ptr.advanced(by: written)
                        remaining -= written
                    }
                    fsync(fd)
                }
            }
            // Restore the default disposition and re-raise so iOS records its
            // own .ips crash log (the ground-truth diagnostic).
            signal(sig, SIG_DFL)
            raise(sig)
        }
        for sig in handledSignals {
            signal(sig, handler)
        }
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
Kind:   NSException (Objective-C)
Name:   \(exception.name.rawValue)
Reason: \(exception.reason ?? "(none)")

Call stack:
\(stack)
"""
    try? report.write(to: url, atomically: true, encoding: .utf8)
}
