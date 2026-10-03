import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openInput = Self("openInput", default: .init(.a, modifiers: [.option]))
    static let screenshot = Self("screenshotTranslate", default: .init(.s, modifiers: [.option]))
    static let translateSelection = Self("translateSelection", default: .init(.d, modifiers: [.option]))
}
