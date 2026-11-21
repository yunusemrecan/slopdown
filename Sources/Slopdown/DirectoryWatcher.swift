// SPDX-License-Identifier: GPL-3.0-or-later
//
// Watches a folder tree with FSEvents, so links, images and the completion list update
// when files are added, removed or renamed (instead of re-checking on a timer).

#if canImport(AppKit)
import CoreServices
import Foundation

final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let onChange: ([String]) -> Void

    init?(root: URL, latency: TimeInterval = 0.3, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            watcher.onChange(list)
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let s = FSEventStreamCreate(nil, callback, &context, [root.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return nil }
        stream = s
        FSEventStreamSetDispatchQueue(s, .main)
        FSEventStreamStart(s)
    }

    deinit {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
#endif
