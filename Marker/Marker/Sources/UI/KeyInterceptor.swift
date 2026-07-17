//
//  KeyInterceptor.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import SwiftUI
import AppKit

/// A transparent NSView that intercepts specific keyboard events via a
/// local event monitor attached to the window.
///
/// Attach this as an overlay on the editor pane to suppress the default
/// Cocoa text system handling of Ctrl+T (transpose characters) and any
/// other key equivalents that should be no-ops inside the text view.
final class KeyInterceptorView: NSView {
    /// Set of key equivalents to suppress. Each entry is a combined key
    /// in the format `"<character>+<modifierFlags.rawValue>"`.
    var suppressedKeys: Set<String> = []
    /// Optional closure invoked when a suppressed key is intercepted.
    /// Receives the character and modifier flags of the suppressed event.
    var onSuppress: ((String, NSEvent.ModifierFlags) -> Void)?

    private var monitor: Any?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        removeMonitor()
        guard let window = newWindow else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = "\(character)+\(modifiers.rawValue)"
            if self.suppressedKeys.contains(key) {
                // Fire the callback before consuming the event
                self.onSuppress?(character, modifiers)
                return nil // consume the event
            }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        removeMonitor()
    }
}

/// SwiftUI wrapper for the key interceptor view.
struct KeyInterceptor: NSViewRepresentable {
    /// Set of shortcut keys to suppress. Each entry is a combined key
    /// in the format `"<character>+<modifierFlags.rawValue>"`.
    var suppressedKeys: Set<String>
    /// Optional closure invoked when a suppressed key is intercepted.
    var onSuppress: ((String, NSEvent.ModifierFlags) -> Void)?

    func makeNSView(context: Context) -> KeyInterceptorView {
        let view = KeyInterceptorView()
        view.suppressedKeys = suppressedKeys
        view.onSuppress = onSuppress
        return view
    }

    func updateNSView(_ nsView: KeyInterceptorView, context: Context) {
        nsView.suppressedKeys = suppressedKeys
        nsView.onSuppress = onSuppress
    }
}

extension View {
    /// Suppress specific keyboard shortcuts across this view hierarchy.
    /// - Parameters:
    ///   - shortcuts: Array of (character, modifierFlags) pairs to consume.
    ///   - onSuppress: Optional callback invoked with each suppressed key's
    ///     character and modifier flags.
    func suppressKeyboardShortcuts(
        _ shortcuts: [(String, NSEvent.ModifierFlags)],
        onSuppress: ((String, NSEvent.ModifierFlags) -> Void)? = nil
    ) -> some View {
        let keys = Set(shortcuts.map { (char, mods) in
            "\(char.lowercased())+\(mods.rawValue)"
        })
        return self.overlay(
            KeyInterceptor(suppressedKeys: keys, onSuppress: onSuppress)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
