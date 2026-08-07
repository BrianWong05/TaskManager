// UI/Elevation/ElevationStatusBar.swift
// Dismissable degradation bar at the top of the content area (spec §6.4):
// explains the current Elevation state and offers "Retry setup".

import SwiftUI

struct ElevationStatusBar: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette
    let onDismiss: () -> Void

    private var status: ElevationStatus { appModel.elevation.status }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: 0x9D5D00))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
            Spacer()
            Button("Retry setup") {
                appModel.elevation.retrySetup()
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(palette.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .buttonStyle(.plain)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: 0x9D5D00).opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }

    private var message: String {
        switch status {
        case .active:
            return ""
        case .signatureExpired:
            return "Background service signature expired. Cross-user details and actions are unavailable. Rebuild the app in Xcode, then Retry setup."
        case .requiresApproval:
            return "Background service is waiting for approval. Enable “Task Manager daemon” in System Settings ▸ Login Items."
        case .notRegistered:
            return "Background service is not set up. Cross-user details, cross-user End task and system Startup toggles are unavailable."
        }
    }
}
