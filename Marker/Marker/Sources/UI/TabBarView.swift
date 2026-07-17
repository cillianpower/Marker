//
//  TabBarView.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI

/// A horizontal tab bar displayed above an editor pane.
struct TabBarView: View {
    let tabs: [Tab]
    @Binding var activeTabId: String?
    var closeTab: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabItemView(
                        tab: tab,
                        isActive: tab.id == activeTabId,
                        closeTab: closeTab
                    )
                    .onTapGesture {
                        activeTabId = tab.id
                    }
                }
            }
        }
        .frame(height: 34)
        .background(.ultraThinMaterial)
    }
}

/// A single tab in the tab bar.
private struct TabItemView: View {
    @ObservedObject var tab: Tab
    let isActive: Bool
    let closeTab: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            if tab.isDirty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
            }

            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)

            Button {
                closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0)
            .frame(width: 16, height: 16)
            .help("Close")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, 1)
    }
}
