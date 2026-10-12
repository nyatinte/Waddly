import Foundation
import Testing
@testable import WaddlyApp

/// Development builds must never resolve to the shipping app's image folder.
struct PetImageLocationTests {
    @Test func theShippingIdentifierUsesTheShippingFolder() {
        #expect(PetImageLocation.directoryName(for: "dev.nyatinte.waddly") == "Waddly")
    }

    @Test(arguments: [
        ("dev.nyatinte.waddly.development", "Waddly-development"),
        ("dev.nyatinte.waddly.setuptest", "Waddly-setuptest"),
        ("dev.nyatinte.waddly.acceptance", "Waddly-acceptance"),
        // Anything that is not the shipping identifier gets a folder of its own, even if it
        // does not follow our naming.
        ("com.example.Waddly", "Waddly-Waddly")
    ])
    func otherIdentifiersGetTheirOwnFolder(identifier: String, expected: String) {
        #expect(PetImageLocation.directoryName(for: identifier) == expected)
    }

    @Test func aMissingIdentifierFallsBackToTheShippingFolder() {
        #expect(PetImageLocation.directoryName(for: nil) == "Waddly")
        #expect(PetImageLocation.directoryName(for: "") == "Waddly")
    }

    @Test func theFolderSitsUnderTheGivenApplicationSupportDirectory() {
        let support = URL(fileURLWithPath: "/tmp/support")
        let url = PetImageLocation.directoryURL(
            for: "dev.nyatinte.waddly.development",
            applicationSupport: support
        )
        #expect(url.path == "/tmp/support/Waddly-development/PetImages")
    }
}
