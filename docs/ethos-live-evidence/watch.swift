import CoreServices
import Foundation

// MARK: - Event

struct Event: Encodable {
    let path: String
    let flags: UInt32
    let id: UInt64
}

let queue = DispatchQueue(label: "quarry-evidence.fsevents")
var events: [Event] = []
let dropped = UInt32(kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagMustScanSubDirs)

func emit(_ value: String) {
    FileHandle.standardOutput.write(Data((value + "\n").utf8))
}

func record(path: String, flags: UInt32, id: UInt64) {
    events.append(Event(path: path, flags: flags, id: id))
}

guard CommandLine.arguments.count >= 2, let stream = FSEventStreamCreate(
    nil, { _, _, count, rawPaths, flags, ids in
        let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as NSArray
        for index in 0 ..< count {
            guard let path = paths[index] as? String else {
                record(path: "", flags: dropped, id: 0)
                continue
            }
            record(path: path, flags: flags[index], id: ids[index])
        }
    }, nil, Array(CommandLine.arguments.dropFirst()) as CFArray,
    FSEventsGetCurrentEventId(), 0.05,
    UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents |
        kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
) else {
    exit(1)
}

FSEventStreamSetDispatchQueue(stream, queue)
guard FSEventStreamStart(stream) else { exit(1) }
emit("ready")
while let line = readLine() {
    if line == "drop" {
        // Inject the documented loss flags through the same collector as the callback.
        queue.sync { record(path: "<injected>", flags: dropped, id: 0) }
        emit("injected")
    } else if line == "cutoff" {
        emit(String(FSEventsGetCurrentEventId()))
    } else if line == "finish" {
        FSEventStreamFlushSync(stream)
        let receipt = queue.sync { events }
        let data = try JSONEncoder().encode(receipt)
        FileHandle.standardOutput.write(data + Data([0x0A]))
        break
    } else {
        exit(1)
    }
}

FSEventStreamStop(stream)
FSEventStreamInvalidate(stream)
FSEventStreamRelease(stream)
