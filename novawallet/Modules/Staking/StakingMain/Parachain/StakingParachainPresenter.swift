import Foundation

final class StakingParachainPresenter {
    weak var view: StakingMainViewProtocol?

    let interactor: StakingParachainInteractorInputProtocol
    let wireframe: StakingParachainWireframeProtocol
    let logger: LoggerProtocol

    let stateMachine: ParaStkStateMachineProtocol
    let networkInfoViewModelFactory: ParaStkNetworkInfoViewModelFactoryProtocol
    let stateViewModelFactory: ParaStkStateViewModelFactoryProtocol

    init(
        interactor: StakingParachainInteractorInputProtocol,
        wireframe: StakingParachainWireframeProtocol,
        networkInfoViewModelFactory: ParaStkNetworkInfoViewModelFactoryProtocol,
        stateViewModelFactory: ParaStkStateViewModelFactoryProtocol,
        logger: LoggerProtocol
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.networkInfoViewModelFactory = networkInfoViewModelFactory
        self.stateViewModelFactory = stateViewModelFactory
        self.logger = logger

        let stateMachine = ParachainStaking.StateMachine()
        self.stateMachine = stateMachine
        stateMachine.delegate = self
    }

    private func provideNetworkInfo() {
        let optCommonData = stateMachine.viewState { (state: ParachainStaking.BaseState) in
            state.commonData
        }

        if
            let networkInfo = optCommonData?.networkInfo,
            let chainAsset = optCommonData?.chainAsset {
            let viewModel = networkInfoViewModelFactory.createViewModel(
                from: networkInfo,
                duration: optCommonData?.stakingDuration,
                chainAsset: chainAsset,
                price: optCommonData?.price
            )
            view?.didRecieveNetworkStakingInfo(viewModel: viewModel)
        } else {
            view?.didRecieveNetworkStakingInfo(viewModel: nil)
        }
    }

    private func provideStateViewModel() {
        let stateViewModel = stateViewModelFactory.createViewModel(from: stateMachine.state)
        view?.didReceiveStakingState(viewModel: stateViewModel)
    }
}

extension StakingParachainPresenter: StakingMainChildPresenterProtocol {
    func setup() {
        view?.didReceiveStatics(viewModel: StakingParachainStatics())

        provideNetworkInfo()
        provideStateViewModel()

        interactor.setup()
    }

    func performMainAction() {
        wireframe.showStakeTokens(from: view, initialDelegator: nil, delegationIdentities: nil)
    }

    func performRewardInfoAction() {
        guard
            let state = stateMachine.viewState(using: { (state: ParachainStaking.BaseState) in state }),
            let rewardCalculator = state.commonData.calculatorEngine,
            let asset = state.commonData.chainAsset?.asset else {
            return
        }

        let maxReward = rewardCalculator.calculateMaxReturn(for: .year)
        let avgReward = rewardCalculator.calculateAvgReturn(for: .year)

        wireframe.showRewardDetails(from: view, maxReward: maxReward, avgReward: avgReward, symbol: asset.symbol)
    }

    func performChangeValidatorsAction() {
        wireframe.showYourCollators(from: view)
    }

    func performSetupValidatorsForBondedAction() {}

    func performStakeMoreAction() {}

    func performRedeemAction() {}

    func performRebondAction() {}

    func performAnalyticsAction() {}

    func performManageAction(_ action: StakingManageOption) {
        switch action {
        case .stakeMore:
            guard let delegator = stateMachine.viewState(
                using: { (state: ParachainStaking.DelegatorState) in state }
            ) else {
                return
            }

            let identities = delegator.delegations?.reduce(into: [AccountId: AccountIdentity]()) { result, item in
                if let identity = item.identity {
                    result[item.accountId] = identity
                }
            }

            wireframe.showStakeTokens(
                from: view,
                initialDelegator: delegator.delegatorState,
                delegationIdentities: identities
            )
        case .unstake:
            break
        case .setupValidators, .changeValidators, .yourValidator:
            wireframe.showYourCollators(from: view)
        default:
            break
        }
    }
}

extension StakingParachainPresenter: StakingParachainInteractorOutputProtocol {
    func didReceiveChainAsset(_ chainAsset: ChainAsset) {
        stateMachine.state.process(chainAsset: chainAsset)
    }

    func didReceiveAccount(_ account: MetaChainAccountResponse?) {
        stateMachine.state.process(account: account)
    }

    func didReceivePrice(_ price: PriceData?) {
        stateMachine.state.process(price: price)

        provideNetworkInfo()
    }

    func didReceiveAssetBalance(_ assetBalance: AssetBalance?) {
        stateMachine.state.process(balance: assetBalance)
    }

    func didReceiveDelegator(_ delegator: ParachainStaking.Delegator?) {
        stateMachine.state.process(delegatorState: delegator)

        let optNewState = stateMachine.viewState { (state: ParachainStaking.DelegatorState) in
            state.delegatorState
        }

        guard let newState = optNewState else {
            stateMachine.state.process(scheduledRequests: nil)
            stateMachine.state.process(delegations: nil)
            return
        }

        interactor.fetchScheduledRequests(for: newState.collators())
        interactor.fetchDelegations(for: newState.collators())
    }

    func didReceiveScheduledRequests(_ requests: [ParachainStaking.DelegatorScheduledRequest]?) {
        stateMachine.state.process(scheduledRequests: requests)
    }

    func didReceiveDelegations(_ delegations: [CollatorSelectionInfo]) {
        stateMachine.state.process(delegations: delegations)
    }

    func didReceiveSelectedCollators(_ collatorsInfo: SelectedRoundCollators) {
        stateMachine.state.process(collatorsInfo: collatorsInfo)
    }

    func didReceiveRewardCalculator(_ calculator: ParaStakingRewardCalculatorEngineProtocol) {
        stateMachine.state.process(calculatorEngine: calculator)
    }

    func didReceiveNetworkInfo(_ networkInfo: ParachainStaking.NetworkInfo) {
        stateMachine.state.process(networkInfo: networkInfo)

        provideNetworkInfo()
    }

    func didReceiveStakingDuration(_ stakingDuration: ParachainStakingDuration) {
        stateMachine.state.process(stakingDuration: stakingDuration)

        provideNetworkInfo()
    }

    func didReceiveBlockNumber(_ blockNumber: BlockNumber?) {
        stateMachine.state.process(blockNumber: blockNumber)
    }

    func didReceiveRoundInfo(_ roundInfo: ParachainStaking.RoundInfo?) {
        stateMachine.state.process(roundInfo: roundInfo)
    }

    func didReceiveTotalReward(_ totalReward: TotalRewardItem?) {
        stateMachine.state.process(totalReward: totalReward)
    }

    func didReceiveError(_ error: Error) {
        logger.error("Did receive error: \(error)")
    }
}

extension StakingParachainPresenter: ParaStkStateMachineDelegate {
    func stateMachineDidChangeState(_: ParaStkStateMachineProtocol) {
        provideStateViewModel()
    }
}
