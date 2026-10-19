import Darwin
import Foundation

/// A file's times from one `stat` call. `FileManager.attributesOfItem` also
/// reads every extended attribute, which adds up when the Roost looks at a
/// handful of files every few seconds.
enum FileTimes {
    static func of(_ path: String) -> (modified: Date, created: Date)? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        func date(_ time: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
        }
        return (date(info.st_mtimespec), date(info.st_birthtimespec))
    }

    static func modified(_ path: String) -> Date? { of(path)?.modified }
}
