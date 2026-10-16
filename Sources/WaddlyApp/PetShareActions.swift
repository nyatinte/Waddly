import AppKit

extension AppDelegate {
    func makePetContextMenu() -> NSMenu {
        let menu = copyMenuTree(statusMenu)
        let shareItem = NSMenuItem(
            title: localizedString(.shareMenu),
            action: #selector(showPetShare),
            keyEquivalent: ""
        )
        shareItem.target = self
        menu.insertItem(shareItem, at: 0)
        menu.insertItem(.separator(), at: 1)
        menu.delegate = self
        return menu
    }

    @objc func showPetShare() {
        guard hasCompletePetImageSet else { return }
        if let shareWindowController, let window = shareWindowController.window, window.isVisible {
            shareWindowController.showWindow(nil)
            presenter.focus(window)
            return
        }
        let controller = PetShareWindowController(
            images: petImages,
            localization: localization,
            presenter: presenter
        )
        controller.onClose = { [weak self] in self?.shareWindowController = nil }
        shareWindowController = controller
        controller.showWindow(nil)
        controller.prepareAssets()
    }
}
