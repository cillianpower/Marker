//
//  EditorSplitView.swift
//  Marker
//
//  Created by Cillian on 09/07/2026.
//

import SwiftUI

/// The main editor area, optionally split into two panes.
struct EditorSplitView: View {
    @ObservedObject var primaryTabManager: TabManager
    @Binding var isSplit: Bool
    var secondaryTabManager: TabManager

    var body: some View {
        if isSplit {
            HSplitView {
                EditorPaneView(tabManager: primaryTabManager)
                    .frame(minWidth: 200)

                EditorPaneView(tabManager: secondaryTabManager)
                    .frame(minWidth: 200)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EditorPaneView(tabManager: primaryTabManager)
        }
    }
}
