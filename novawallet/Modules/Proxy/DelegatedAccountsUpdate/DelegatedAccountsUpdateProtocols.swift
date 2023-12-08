import RobinHood

protocol DelegatedAccountsUpdateViewProtocol: ControllerBackedProtocol {
    func didReceive(
        delegatedModels: [ProxyWalletView.ViewModel],
        revokedModels: [ProxyWalletView.ViewModel]
    )
    func preferredContentHeight(
        delegatedModels: [ProxyWalletView.ViewModel],
        revokedModels: [ProxyWalletView.ViewModel]
    ) -> CGFloat
}

protocol DelegatedAccountsUpdatePresenterProtocol: AnyObject {
    func setup()
    func done()
    func showInfo()
}

protocol DelegatedAccountsUpdateInteractorInputProtocol: AnyObject {
    func setup()
}

protocol DelegatedAccountsUpdateInteractorOutputProtocol: AnyObject {
    func didReceiveWalletsChanges(_ changes: [DataProviderChange<ManagedMetaAccountModel>])
    func didReceiveChainChanges(_ changes: [DataProviderChange<ChainModel>])
    func didReceiveError(_ error: DelegatedAccountsUpdateError)
}

protocol DelegatedAccountsUpdateWireframeProtocol: AnyObject, WebPresentable {
    func close(from view: ControllerBackedProtocol?)
}

enum DelegatedAccountsUpdateError: Error {
    case subscription(Error)
}
