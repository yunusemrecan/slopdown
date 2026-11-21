// SPDX-License-Identifier: GPL-3.0-or-later
//
// UI strings: the English text is the key; translations live in
// Resources/<lang>.lproj/Localizable.strings (copied into the app by build_app.sh).

#if canImport(AppKit)
import Foundation

/// Localized UI text.
func L(_ english: String) -> String {
    NSLocalizedString(english, comment: "")
}

/// Localized format string (`%@`, `%d`) filled with arguments.
func LF(_ english: String, _ args: CVarArg...) -> String {
    String(format: L(english), arguments: args)
}
#endif
