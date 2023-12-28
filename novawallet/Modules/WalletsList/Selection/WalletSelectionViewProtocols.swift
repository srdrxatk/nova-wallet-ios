import Foundation

protocol WalletSelectionPresenterProtocol: WalletsListPresenterProtocol {
    func selectItem(at index: Int, section: Int)
    func activateSettings()
    func viewWillDisappear()
}

protocol WalletSelectionInteractorInputProtocol: WalletsListInteractorInputProtocol {
    func select(item: ManagedMetaAccountModel)
    func updateWalletsStatuses()
}

protocol WalletSelectionInteractorOutputProtocol: WalletsListInteractorOutputProtocol {
    func didCompleteSelection()
    func didReceive(saveError: Error)
}

protocol WalletSelectionWireframeProtocol: WalletsListWireframeProtocol {
    func close(view: WalletsListViewProtocol?)
    func showSettings(from view: WalletsListViewProtocol?)
    func showProxiedsUpdates(
        from view: ControllerBackedProtocol?,
        initWallets: [ManagedMetaAccountModel]
    )
}
