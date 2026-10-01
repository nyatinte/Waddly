import Foundation

/// UserDefaults is thread-safe, and this wrapper stores no other mutable state.
final class AppSettings: @unchecked Sendable {
    private enum Key {
        static let appLanguage = "appLanguage"
        static let breathingEnabled = "breathingEnabled"
        static let displaySize = "displaySize"
        static let panelOrigin = "panelOrigin"
        static let petImageFiles = "petImageFiles"
        static let setupWizardSeen = "setupWizardSeen"
        static let showInDock = "showInDock"
        static let showInMenuBar = "showInMenuBar"
        static let typingMotion = "typingMotion"
    }

    private enum Default {
        static let appLanguage: AppLanguage = .system
        static let breathingEnabled = true
        static let displaySize: CGFloat = 240
        static let petImageFiles: [String: [String]] = [:]
        static let setupWizardSeen = false
        static let showInDock = true
        static let showInMenuBar = true
        static let typingMotion: TypingMotion = .weak
    }

    static let standard = AppSettings(defaults: .standard)

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func registerDefaults() {
        defaults.register(defaults: [
            Key.appLanguage: Default.appLanguage.rawValue,
            Key.breathingEnabled: Default.breathingEnabled,
            Key.displaySize: Double(Default.displaySize),
            Key.setupWizardSeen: Default.setupWizardSeen,
            Key.showInDock: Default.showInDock,
            Key.showInMenuBar: Default.showInMenuBar,
            Key.typingMotion: Default.typingMotion.rawValue
        ])
    }

    var appLanguage: AppLanguage {
        get {
            let storedValue = defaults.object(forKey: Key.appLanguage) as? Int
            return storedValue.flatMap(AppLanguage.init(rawValue:)) ?? Default.appLanguage
        }
        set { defaults.set(newValue.rawValue, forKey: Key.appLanguage) }
    }

    var breathingEnabled: Bool {
        get { defaults.object(forKey: Key.breathingEnabled) as? Bool ?? Default.breathingEnabled }
        set { defaults.set(newValue, forKey: Key.breathingEnabled) }
    }

    var displaySize: CGFloat {
        get {
            let value = defaults.object(forKey: Key.displaySize) as? Double ?? Double(Default.displaySize)
            return value == 0 ? Default.displaySize : CGFloat(value)
        }
        set { defaults.set(Double(newValue), forKey: Key.displaySize) }
    }

    var panelOrigin: [Double]? {
        get { defaults.array(forKey: Key.panelOrigin) as? [Double] }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.panelOrigin)
            } else {
                defaults.removeObject(forKey: Key.panelOrigin)
            }
        }
    }

    var petImageFiles: [String: [String]] {
        get { defaults.dictionary(forKey: Key.petImageFiles) as? [String: [String]] ?? Default.petImageFiles }
        set { defaults.set(newValue, forKey: Key.petImageFiles) }
    }

    var setupWizardSeen: Bool {
        get { defaults.object(forKey: Key.setupWizardSeen) as? Bool ?? Default.setupWizardSeen }
        set { defaults.set(newValue, forKey: Key.setupWizardSeen) }
    }

    var showInDock: Bool {
        get { defaults.object(forKey: Key.showInDock) as? Bool ?? Default.showInDock }
        set { defaults.set(newValue, forKey: Key.showInDock) }
    }

    var showInMenuBar: Bool {
        get { defaults.object(forKey: Key.showInMenuBar) as? Bool ?? Default.showInMenuBar }
        set { defaults.set(newValue, forKey: Key.showInMenuBar) }
    }

    var typingMotion: TypingMotion {
        get {
            let storedValue = defaults.object(forKey: Key.typingMotion) as? Int
            return storedValue.flatMap(TypingMotion.init(rawValue:)) ?? Default.typingMotion
        }
        set { defaults.set(newValue.rawValue, forKey: Key.typingMotion) }
    }

    func ensurePresenceIsVisible() {
        if !showInDock, !showInMenuBar {
            showInDock = true
        }
    }

    func removeSetupWizardSeen() {
        defaults.removeObject(forKey: Key.setupWizardSeen)
    }
}
