import Observation
import ServiceManagement

/// Launch at login, through the system's login-item service, which works in
/// the sandbox. The system remembers the choice, so this reads it back from
/// there rather than keeping its own copy.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status

    /// On, or waiting for the listener to allow it in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The status read back below shows what actually happened.
        }
        refresh()
    }

    /// The listener may change it in System Settings › Login Items.
    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
