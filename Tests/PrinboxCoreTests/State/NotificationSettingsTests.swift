import Testing

@testable import PrinboxCore

@MainActor
@Suite struct NotificationSettingsTests {
    @Test func offByDefaultAndPersists() {
        let defaults = MemoryDefaults()
        let settings = NotificationSettings(defaults: defaults)
        #expect(settings.isEnabled == false)
        settings.setEnabled(true)
        #expect(defaults.object(forKey: NotificationSettings.key) as? Bool == true)
        #expect(NotificationSettings(defaults: defaults).isEnabled == true)
    }

    @Test func statusNotesExplainDeniedAndUnavailable() {
        #expect(
            NotificationStatus.denied.note
                == "Notifications are off for PRInbox. Turn them on in System Settings › Notifications.")
        #expect(NotificationStatus.unavailable.note == "Not available when run from the build directory.")
        #expect(NotificationStatus.authorized.note == nil)
        #expect(NotificationStatus.notDetermined.note == nil)
    }
}
