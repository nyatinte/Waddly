import Foundation

/// Where imported pet frames live on disk.
///
/// Development builds must never share this folder with the shipping app: a test run would
/// otherwise overwrite the images belonging to the user's installed copy.
enum PetImageLocation {
    static let shippingBundleIdentifier = "dev.nyatinte.waddly"

    /// `Waddly` for the shipping app, `Waddly-<suffix>` for anything else.
    static func directoryName(for bundleIdentifier: String?) -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              bundleIdentifier != shippingBundleIdentifier
        else {
            return "Waddly"
        }
        let suffix = bundleIdentifier.split(separator: ".").last.map(String.init) ?? "development"
        return "Waddly-\(suffix)"
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
