// UI/Elevation/ElevationSetupSheet.swift
// First-launch guided setup (spec §6.3): explain why the background service
// is needed → SMAppService registration → system approval prompt. Declining
// drops the app into degraded mode (§6.4) without nagging again.

import SwiftUI

struct ElevationSetupSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.accent)
                Text("Set up the background service")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }

            Text("""
            Task Manager works fully without extra permissions, but some features need a small privileged helper (a launchd daemon registered with Apple's SMAppService):

            • CPU, memory and disk details of other users' processes
            • End task / Force Quit on processes owned by other users
            • Enabling or disabling system-wide Startup items

            macOS will ask you to approve the background item in System Settings.
            """)
            .font(.system(size: 12))
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0xC42B1C))
            }

            HStack {
                Spacer()
                Button("Later") {
                    appModel.elevation.setupDeclined = true
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(palette.subdued)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Button("Set Up…") {
                    do {
                        try appModel.elevation.register()
                        dismiss()
                    } catch {
                        errorMessage = "Registration failed: \(error.localizedDescription)"
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(palette.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(palette.card)
    }
}
