//
//  SettingsView.swift
//  Marker
//
//  Created by Cillian on 13/07/2026.
//

import SwiftUI
import AppKit

/// Minimal settings window for Marker.
/// Currently provides the window material switcher (frosted/glass/opaque)
/// with live preview — no restart needed.
struct SettingsView: View {
    @AppStorage("windowMaterial") private var windowMaterial: String = "frosted"
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.85

    var body: some View {
        TabView {
            appearancePane
                .tabItem {
                    Image(systemName: "paintbrush")
                    Text("Appearance")
                }
        }
        .frame(width: 380, height: 220)
    }

    // MARK: - Appearance pane

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Window Material ──
            VStack(alignment: .leading, spacing: 8) {
                Text("Window Material")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("", selection: $windowMaterial) {
                    Text("Frosted (blur)").tag("frosted")
                    Text("Glass").tag("glass")
                    Text("Opaque").tag("opaque")
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // ── Glass opacity ──
            if windowMaterial == "glass" {
                HStack {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Slider(value: $backgroundOpacity, in: 0...1, step: 0.05)
                    Text("\(Int(backgroundOpacity * 100))%")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            Spacer()

            // ── Footer ──
            HStack {
                Text("Settings apply instantly and persist between launches.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Reset") {
                    withAnimation {
                        windowMaterial = "frosted"
                        backgroundOpacity = 0.85
                    }
                }
                .controlSize(.small)
                .buttonStyle(.link)
                .font(.footnote)
            }
        }
        .padding(20)
    }
}

#Preview("Settings") {
    SettingsView()
}
