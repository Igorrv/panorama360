import Foundation
import OSLog

/// Thin wrapper around `os.Logger` with per-subsystem categories.
public enum Log {
    private static let subsystem = "com.teleport.panorama360"

    public static let app      = Logger(subsystem: subsystem, category: "app")
    public static let camera   = Logger(subsystem: subsystem, category: "camera")
    public static let motion   = Logger(subsystem: subsystem, category: "motion")
    public static let ar       = Logger(subsystem: subsystem, category: "ar")
    public static let capture  = Logger(subsystem: subsystem, category: "capture")
    public static let guide    = Logger(subsystem: subsystem, category: "guide")
    public static let stitch   = Logger(subsystem: subsystem, category: "stitch")
    public static let viewer   = Logger(subsystem: subsystem, category: "viewer")
    public static let recon    = Logger(subsystem: subsystem, category: "recon")
    public static let storage  = Logger(subsystem: subsystem, category: "storage")
}
