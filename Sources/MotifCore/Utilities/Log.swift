import os

/// Central loggers. No telemetry — logs stay on the machine.
public enum Log {
    public static let general = Logger(subsystem: "com.motif.app", category: "general")
    public static let device = Logger(subsystem: "com.motif.app", category: "device")
    public static let media = Logger(subsystem: "com.motif.app", category: "media")
    public static let library = Logger(subsystem: "com.motif.app", category: "library")
    public static let apply = Logger(subsystem: "com.motif.app", category: "apply")
}
