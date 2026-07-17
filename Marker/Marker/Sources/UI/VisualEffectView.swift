//
//  VisualEffectView.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import SwiftUI
import AppKit

// MARK: - Visual effect (frosted blur)

/// An `NSViewRepresentable` wrapping `NSVisualEffectView` for the "frosted" material style.
/// Provides the standard macOS translucency seen in apps like Bear, Obsidian, and Xcode.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = state
    }
}

// MARK: - Window blur (private CGS API for "glass" on macOS 15)

/// Matches Ghostty's use of CGSSetWindowBackgroundBlurRadius with sentinel
/// values for glass effects. This is a private CoreGraphics API shared by
/// Terminal.app, iTerm2, Ghostty, and most other macOS terminal emulators.
/// Used on macOS 15 (and any pre-26 release) to achieve the "glass" material.
enum WindowBlur {
    /// Applies the macos-glass-regular blur to a window.
    static func applyGlassBlur(to window: NSWindow) {
        let radius: Int32 = -1  // Sentinel for macos-glass-regular
        setWindowBackgroundBlur(window: window, radius: radius)
    }

    /// Removes the glass blur and restores standard compositing.
    static func removeGlassBlur(from window: NSWindow) {
        let radius: Int32 = 0
        setWindowBackgroundBlur(window: window, radius: radius)
    }

    private static let setBlur: (@convention(c) (Int, Int, Int32) -> Int32)? = {
        let handle = dlopen(nil, RTLD_NOLOAD)
        guard let sym = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (Int, Int, Int32) -> Int32).self)
    }()

    private static let defaultConnection: (@convention(c) () -> Int)? = {
        let handle = dlopen(nil, RTLD_NOLOAD)
        guard let sym = dlsym(handle, "CGSDefaultConnectionForThread") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) () -> Int).self)
    }()

    private static func setWindowBackgroundBlur(window: NSWindow, radius: Int32) {
        guard let setBlur, let defaultConnection else { return }
        let conn = defaultConnection()
        let winNum = window.windowNumber
        _ = setBlur(conn, winNum, radius)
    }
}

// MARK: - Window accessor

/// An `NSViewRepresentable` that provides access to the enclosing `NSWindow`.
/// Used by `WindowConfigurator` to apply window-level properties from SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }
}
