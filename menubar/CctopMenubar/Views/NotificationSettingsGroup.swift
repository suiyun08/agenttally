import SwiftUI

/// The Notifications toggle and, while notifications are on, one sound picker per event.
struct NotificationSettingsGroup: View {
    @ObservedObject var notificationPermission: NotificationPermissionController

    var body: some View {
        VStack(spacing: 0) {
            NotificationSettingsRow(notificationPermission: notificationPermission)
            if showsSounds {
                ForEach(AlertSoundEvent.allCases, id: \.self) { event in
                    Rectangle()
                        .fill(Color.groupedRowBorder)
                        .frame(height: 0.5)
                        .padding(.leading, AppChrome.settingsDividerLeadingPadding)
                    AlertSoundSettingsRow(event: event)
                }
            }
        }
    }

    private var showsSounds: Bool {
        switch notificationPermission.state {
        case .enabled, .pendingSystemPermission: true
        case .off, .enabling, .needsSystemPermission, .failed: false
        }
    }
}

/// Picks the sound for one event; picking plays it once.
struct AlertSoundSettingsRow: View {
    let event: AlertSoundEvent
    @AppStorage private var selection: String

    init(event: AlertSoundEvent) {
        self.event = event
        _selection = AppStorage(wrappedValue: event.defaultSound.rawValue, event.defaultsKey)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(event.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker(event.title, selection: $selection) {
                ForEach(AlertSound.allCases, id: \.self) { sound in
                    Text(sound.label).tag(sound.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .onChange(of: selection) { AlertSound(rawValue: $0)?.preview() }
        }
        .padding(.horizontal, AppChrome.settingsRowHorizontalPadding)
        .padding(.vertical, 4)
        .frame(minHeight: 25)
    }
}
