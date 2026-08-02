import AppKit
import Foundation

protocol NotificationDialogPresenting {
    func requestTelegramCredentials(hasStoredToken: Bool,
                                    completion: (TelegramCredentialInput?) -> Void)
    func requestSynologyCredentials(hasStoredPassword: Bool,
                                    completion: (SynologyCredentialInput?) -> Void)
    func showResult(title: String, message: String)
}

struct TelegramCredentialInput {
    let replacementToken: String?
    let chatID: String
}

struct SynologyCredentialInput {
    let webhookURL: String
    let username: String
    let password: String?
    let channelID: String
}

final class NotificationMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    let channelItems: [NotificationChannel: NSMenuItem]
    let enableItem: NSMenuItem
    let testItem: NSMenuItem
    let statusItem: NSMenuItem
    let eventItems: [NotificationEvent: NSMenuItem]
    let photoItem: NSMenuItem
    let privacyItem: NSMenuItem
    let locationItem: NSMenuItem

    private let settings: NotificationSettings
    private let service: NotificationHandling
    private let dialogs: NotificationDialogPresenting
    private let locationAuthorization: LocationAuthorizationRequesting
    private let hostName: () -> String
    private let serviceQueue = DispatchQueue(label: "jp.sone.BLEUnlock.notification.menu",
                                             qos: .utility)

    init(settings: NotificationSettings,
         service: NotificationHandling,
         dialogs: NotificationDialogPresenting,
         locationAuthorization: LocationAuthorizationRequesting = CoreMacLocationProvider(),
         hostName: @escaping () -> String = { Host.current().localizedName ?? "Mac" }) {
        self.settings = settings
        self.service = service
        self.dialogs = dialogs
        self.locationAuthorization = locationAuthorization
        self.hostName = hostName

        let channelMenu = NSMenu()
        channelMenu.autoenablesItems = false
        var builtChannelItems: [NotificationChannel: NSMenuItem] = [:]
        for channel in NotificationChannel.allCases {
            let key = channel == .telegram
                ? "notification_channel_telegram"
                : "notification_channel_synology_chat"
            let item = NSMenuItem(title: t(key),
                                  action: #selector(selectChannel(_:)),
                                  keyEquivalent: "")
            builtChannelItems[channel] = item
            channelMenu.addItem(item)
        }
        channelItems = builtChannelItems

        let channelItem = NSMenuItem(title: t("notification_channel"),
                                     action: nil,
                                     keyEquivalent: "")
        channelItem.submenu = channelMenu

        enableItem = NSMenuItem(title: t("notification_enable"),
                                action: #selector(toggleEnabled(_:)),
                                keyEquivalent: "")
        let configureItem = NSMenuItem(title: t("notification_configure"),
                                       action: #selector(configure),
                                       keyEquivalent: "")
        testItem = NSMenuItem(title: t("notification_test"),
                              action: #selector(sendTest),
                              keyEquivalent: "")

        let eventsMenu = NSMenu()
        eventsMenu.autoenablesItems = false
        var items: [NotificationEvent: NSMenuItem] = [:]
        for event in NotificationEvent.allCases {
            let item = NSMenuItem(title: t("telegram_event_\(event.rawValue)"),
                                  action: #selector(toggleEvent(_:)),
                                  keyEquivalent: "")
            items[event] = item
            eventsMenu.addItem(item)
        }
        eventItems = items

        let eventsItem = NSMenuItem(title: t("notification_events"),
                                    action: nil,
                                    keyEquivalent: "")
        eventsItem.submenu = eventsMenu
        photoItem = NSMenuItem(title: t("notification_take_photo"),
                               action: #selector(togglePhoto(_:)),
                               keyEquivalent: "")
        privacyItem = NSMenuItem(title: t("telegram_camera_privacy"),
                                 action: nil,
                                 keyEquivalent: "")
        privacyItem.isEnabled = false
        locationItem = NSMenuItem(title: t("notification_attach_mac_location"),
                                  action: #selector(toggleLocation(_:)),
                                  keyEquivalent: "")
        statusItem = NSMenuItem(title: t("notification_status_not_configured"),
                                action: nil,
                                keyEquivalent: "")
        statusItem.isEnabled = false

        super.init()

        channelItems.values.forEach { $0.target = self }
        enableItem.target = self
        configureItem.target = self
        testItem.target = self
        eventItems.values.forEach { $0.target = self }
        photoItem.target = self
        locationItem.target = self

        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(channelItem)
        menu.addItem(enableItem)
        menu.addItem(configureItem)
        menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(eventsItem)
        menu.addItem(photoItem)
        menu.addItem(privacyItem)
        menu.addItem(locationItem)
        menu.addItem(.separator())
        menu.addItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let channel = settings.selectedChannel
        for (candidate, item) in channelItems {
            item.state = candidate == channel ? .on : .off
        }
        let configured = (try? settings.isConfigured(channel)) == true
        enableItem.isEnabled = configured
        testItem.isEnabled = configured
        enableItem.state = configured && settings.isEnabled(channel) ? .on : .off
        for (event, item) in eventItems {
            item.state = settings.isEventEnabled(event) ? .on : .off
        }
        photoItem.state = settings.takePhotoOnIntruded(channel) ? .on : .off
        privacyItem.title = channel == .telegram
            ? t("telegram_camera_privacy")
            : t("notification_camera_privacy_synology")
        locationItem.state = settings.attachMacLocation(channel) ? .on : .off
        locationItem.isEnabled = settings.takePhotoOnIntruded(channel)

        if !configured {
            statusItem.title = t("notification_status_not_configured")
        } else if settings.isEnabled(channel) {
            statusItem.title = t("notification_status_enabled")
        } else {
            statusItem.title = t("notification_status_disabled")
        }
    }

    @objc internal func selectChannel(_ item: NSMenuItem) {
        guard let channel = channelItems.first(where: { $0.value === item })?.key else { return }
        settings.selectedChannel = channel
        menuWillOpen(menu)
    }

    @objc internal func toggleEnabled(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        guard (try? settings.isConfigured(channel)) == true else {
            menuWillOpen(menu)
            return
        }
        settings.setEnabled(!settings.isEnabled(channel), for: channel)
        menuWillOpen(menu)
    }

    @objc internal func toggleEvent(_ item: NSMenuItem) {
        guard let event = eventItems.first(where: { $0.value === item })?.key else { return }
        settings.setEvent(event, enabled: !settings.isEventEnabled(event))
        item.state = settings.isEventEnabled(event) ? .on : .off
    }

    @objc internal func togglePhoto(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        settings.setTakePhotoOnIntruded(!settings.takePhotoOnIntruded(channel), for: channel)
        menuWillOpen(menu)
    }

    @objc internal func toggleLocation(_ item: NSMenuItem) {
        let channel = settings.selectedChannel
        guard settings.takePhotoOnIntruded(channel) else {
            menuWillOpen(menu)
            return
        }
        settings.setAttachMacLocation(!settings.attachMacLocation(channel), for: channel)
        if settings.attachMacLocation(channel) {
            locationAuthorization.requestAuthorization()
        }
        menuWillOpen(menu)
    }

    @objc internal func configure() {
        switch settings.selectedChannel {
        case .telegram:
            configureTelegram()
        case .synologyChat:
            configureSynology()
        }
    }

    private func configureTelegram() {
        let configured: Bool
        do {
            configured = try settings.isConfigured(.telegram)
        } catch {
            dialogs.showResult(title: t("notification_configure"),
                               message: t("notification_error_settings_unavailable"))
            return
        }

        dialogs.requestTelegramCredentials(hasStoredToken: configured) { input in
            guard let input = input else { return }
            do {
                try self.settings.saveTelegramCredentials(replacementToken: input.replacementToken,
                                                          chatID: input.chatID)
                guard try self.settings.isConfigured(.telegram) else {
                    self.dialogs.showResult(
                        title: t("notification_configure"),
                        message: t("notification_error_not_configured")
                    )
                    return
                }
                self.menuWillOpen(self.menu)
            } catch {
                self.dialogs.showResult(title: t("notification_configure"),
                                        message: error.localizedDescription)
            }
        }
    }

    private func configureSynology() {
        let configured: Bool
        do {
            configured = try settings.isConfigured(.synologyChat)
        } catch {
            dialogs.showResult(title: t("notification_configure"),
                               message: t("notification_error_settings_unavailable"))
            return
        }

        dialogs.requestSynologyCredentials(hasStoredPassword: configured) { input in
            guard let input = input else { return }
            do {
                try self.settings.saveSynologyCredentials(webhookURL: input.webhookURL,
                                                          username: input.username,
                                                          password: input.password,
                                                          channelID: input.channelID)
                guard try self.settings.isConfigured(.synologyChat) else {
                    self.dialogs.showResult(
                        title: t("notification_configure"),
                        message: t("notification_error_not_configured")
                    )
                    return
                }
                self.menuWillOpen(self.menu)
            } catch {
                self.dialogs.showResult(title: t("notification_configure"),
                                        message: error.localizedDescription)
            }
        }
    }

    @objc internal func sendTest() {
        let service = self.service
        let resolvedHostName = hostName()
        serviceQueue.async { [weak self] in
            service.sendTest(hostName: resolvedHostName) { result in
                self?.showTestResult(result)
            }
        }
    }

    private func showTestResult(_ result: Result<Void, Error>) {
        onMain { [weak self] in
            guard let self = self else { return }
            switch result {
            case .success:
                self.dialogs.showResult(title: t("notification_test_success"), message: "")
            case .failure(let error):
                self.dialogs.showResult(title: t("notification_test_failed"),
                                        message: error.localizedDescription)
            }
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}

final class AppKitNotificationDialogPresenter: NotificationDialogPresenting {
    func requestTelegramCredentials(hasStoredToken: Bool,
                                    completion: (TelegramCredentialInput?) -> Void) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = t("notification_configure")
        alert.addButton(withTitle: t("notification_save"))
        alert.addButton(withTitle: t("cancel"))

        let explanation = NSTextField(wrappingLabelWithString: t("telegram_setup_help"))
        explanation.preferredMaxLayoutWidth = 360
        let privacy = NSTextField(wrappingLabelWithString: t("telegram_camera_privacy"))
        privacy.preferredMaxLayoutWidth = 360

        let tokenLabel = NSTextField(labelWithString: t("telegram_bot_token"))
        let tokenField = NSSecureTextField()
        tokenField.stringValue = ""
        tokenField.placeholderString = hasStoredToken ? nil : t("telegram_bot_token")

        let chatIDLabel = NSTextField(labelWithString: t("telegram_chat_id"))
        let chatIDField = NSTextField()

        let stack = NSStackView(views: [explanation,
                                        privacy,
                                        tokenLabel,
                                        tokenField,
                                        chatIDLabel,
                                        chatIDField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 190)
        tokenField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        chatIDField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(nil)
            return
        }

        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        completion(.init(replacementToken: token.isEmpty ? nil : token,
                         chatID: chatIDField.stringValue))
    }

    func requestSynologyCredentials(hasStoredPassword: Bool,
                                    completion: (SynologyCredentialInput?) -> Void) {
        precondition(Thread.isMainThread)

        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = t("notification_configure")
        alert.addButton(withTitle: t("notification_save"))
        alert.addButton(withTitle: t("cancel"))

        let explanation = NSTextField(wrappingLabelWithString: t("synology_setup_help"))
        explanation.preferredMaxLayoutWidth = 360
        let privacy = NSTextField(wrappingLabelWithString: t("notification_camera_privacy_synology"))
        privacy.preferredMaxLayoutWidth = 360

        let urlLabel = NSTextField(labelWithString: t("synology_webhook_url"))
        let urlField = NSTextField()
        let usernameLabel = NSTextField(labelWithString: t("synology_username"))
        let usernameField = NSTextField()
        let passwordLabel = NSTextField(labelWithString: t("synology_password"))
        let passwordField = NSSecureTextField()
        passwordField.stringValue = ""
        passwordField.placeholderString = hasStoredPassword ? nil : t("synology_password")
        let channelIDLabel = NSTextField(labelWithString: t("synology_channel_id"))
        let channelIDField = NSTextField()

        let stack = NSStackView(views: [explanation,
                                        privacy,
                                        urlLabel,
                                        urlField,
                                        usernameLabel,
                                        usernameField,
                                        passwordLabel,
                                        passwordField,
                                        channelIDLabel,
                                        channelIDField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 330)
        for field in [urlField, usernameField, passwordField, channelIDField] {
            field.widthAnchor.constraint(equalToConstant: 360).isActive = true
        }
        alert.accessoryView = stack

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            completion(nil)
            return
        }

        let password = passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        completion(.init(webhookURL: urlField.stringValue,
                         username: usernameField.stringValue,
                         password: password.isEmpty ? nil : password,
                         channelID: channelIDField.stringValue))
    }

    func showResult(title: String, message: String) {
        precondition(Thread.isMainThread)
        let alert = NSAlert()
        alert.window.title = "BLEUnlock"
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: t("ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
