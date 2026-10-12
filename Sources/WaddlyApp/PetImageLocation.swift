import Foundation

/// Where imported pet frames live on disk.
///
/// Development builds must never share this folder with the shipping app: a test run would
/// otherwise overwrite the images belonging to the user's installed copy.
enum PetImageLocation {
    static let shippingBundleIdentifier = "dev.nyatinte.waddly"

    /// `Waddly` for the shipping app, `Waddly-<suffix>` for anything else.
    ///
    /// The whole suffix after the shipping identifier is kept. Taking only the last dotted component
    /// mapped `dev.nyatinte.waddly.setup.development` and `dev.nyatinte.waddly.development` to the
    /// same folder, while the variants exist precisely to be kept apart.
    static func directoryName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              bundleIdentifier != shippingBundleIdentifier
        else {
            return "Waddly"
        }
        let prefix = shippingBundleIdentifier + "."
        let suffix = bundleIdentifier.hasPrefix(prefix)
            ? String(bundleIdentifier.dropFirst(prefix.count))
            // An identifier of someone else's making still gets a folder of its own.
            : bundleIdentifier.replacingOccurrences(of: ".", with: "-")
        return "Waddly-" + (suffix.isEmpty ? "development" : suffix)
    }

    static func directoryURL(
        for bundleIdentifier: String?,
        applicationSupport: URL
    ) -> URL {
        applicationSupport
            .appendingPathComponent(directoryName(for: bundleIdentifier), isDirectory: true)
            .appendingPathComponent("PetImages", isDirectory: true)
    }
}
