import os

enum Log {
    private static let subsystem = "io.github.marvika.BarnOwl"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")
    static let keepAwake = Logger(subsystem: subsystem, category: "keepawake")
}
