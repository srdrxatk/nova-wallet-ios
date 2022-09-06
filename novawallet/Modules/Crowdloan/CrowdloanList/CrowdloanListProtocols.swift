import SoraFoundation

protocol CrowdloanListViewProtocol: ControllerBackedProtocol, AlertPresentable, LoadableViewProtocol {
    func didReceive(walletSwitchViewModel: WalletSwitchViewModel)
    func didReceive(chainInfo: CrowdloansChainViewModel)
    func didReceive(listState: CrowdloanListState)
}

protocol CrowdloanListPresenterProtocol: AnyObject {
    func setup()
    func refresh(shouldReset: Bool)
    func selectCrowdloan(_ paraId: ParaId)
    func becomeOnline()
    func putOffline()
    func selectChain()
    func handleYourContributions()
    func handleWalletSwitch()
}

protocol CrowdloanListInteractorInputProtocol: AnyObject {
    func setup()
    func refresh()
    func saveSelected(chainModel: ChainModel)
    func becomeOnline()
    func putOffline()
}

protocol CrowdloanListInteractorOutputProtocol: AnyObject {
    func didReceiveCrowdloans(result: Result<[Crowdloan], Error>)
    func didReceiveDisplayInfo(result: Result<CrowdloanDisplayInfoDict, Error>)
    func didReceiveBlockNumber(result: Result<BlockNumber?, Error>)
    func didReceiveBlockDuration(result: Result<BlockTime, Error>)
    func didReceiveLeasingPeriod(result: Result<LeasingPeriod, Error>)
    func didReceiveLeasingOffset(result: Result<LeasingOffset, Error>)
    func didReceiveContributions(result: Result<CrowdloanContributionDict, Error>)
    func didReceiveExternalContributions(result: Result<[ExternalContribution], Error>)
    func didReceiveLeaseInfo(result: Result<ParachainLeaseInfoDict, Error>)
    func didReceiveSelectedChain(result: Result<ChainModel, Error>)
    func didReceiveAccountInfo(result: Result<AccountInfo?, Error>)
    func didReceive(wallet: MetaAccountModel)
    func didReceivePriceData(result: Result<PriceData?, Error>?)
}

protocol CrowdloanListWireframeProtocol: AnyObject, WalletSwitchPresentable {
    func presentContributionSetup(
        from view: CrowdloanListViewProtocol?,
        crowdloan: Crowdloan,
        displayInfo: CrowdloanDisplayInfo?
    )

    func showYourContributions(
        crowdloans: [Crowdloan],
        viewInfo: CrowdloansViewInfo,
        chainAsset: ChainAssetDisplayInfo,
        from view: ControllerBackedProtocol?
    )

    func selectChain(
        from view: ControllerBackedProtocol?,
        delegate: AssetSelectionDelegate,
        selectedChainAssetId: ChainAssetId?
    )
}
