// SPDX-License-Identifier: GPL-3.0-or-later

#if canImport(AppKit)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#endif
