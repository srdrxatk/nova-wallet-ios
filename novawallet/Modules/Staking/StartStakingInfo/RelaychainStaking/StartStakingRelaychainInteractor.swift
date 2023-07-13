import RobinHood
import BigInt
import Foundation
import SubstrateSdk

final class StartStakingRelaychainInteractor: StartStakingInfoBaseInteractor, AnyCancellableCleaning {
    let chainRegistry: ChainRegistryProtocol
    let stateFactory: RelaychainStakingStateFactoryProtocol
    let stakingAccountUpdatingService: StakingAccountUpdatingServiceProtocol

    var stakingLocalSubscriptionFactory: StakingLocalSubscriptionFactoryProtocol

    private var minNominatorBondProvider: AnyDataProvider<DecodedBigUInt>?
    private var bagListSizeProvider: AnyDataProvider<DecodedU32>?
    private var eraCompletionTimeCancellable: CancellableCall?
    private var networkInfoCancellable: CancellableCall?
    private var rewardCalculatorCancellable: CancellableCall?
    private var sharedState: StakingSharedState?

    weak var presenter: StartStakingInfoRelaychainInteractorOutputProtocol? {
        didSet {
            basePresenter = presenter
        }
    }

    init(
        chainAsset: ChainAsset,
        selectedWalletSettings: SelectedWalletSettings,
        walletLocalSubscriptionFactory: WalletLocalSubscriptionFactoryProtocol,
        priceLocalSubscriptionFactory: PriceProviderFactoryProtocol,
        stakingAssetSubscriptionService: StakingRemoteSubscriptionServiceProtocol,
        stakingAccountUpdatingService: StakingAccountUpdatingServiceProtocol,
        currencyManager: CurrencyManagerProtocol,
        stateFactory: RelaychainStakingStateFactoryProtocol,
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue
    ) {
        self.stateFactory = stateFactory
        self.chainRegistry = chainRegistry
        self.stakingAccountUpdatingService = stakingAccountUpdatingService
        stakingLocalSubscriptionFactory = stateFactory.stakingLocalSubscriptionFactory

        super.init(
            selectedWalletSettings: selectedWalletSettings,
            selectedChainAsset: chainAsset,
            walletLocalSubscriptionFactory: walletLocalSubscriptionFactory,
            priceLocalSubscriptionFactory: priceLocalSubscriptionFactory,
            stakingAssetSubscriptionService: stakingAssetSubscriptionService,
            currencyManager: currencyManager,
            operationQueue: operationQueue
        )
    }

    private func provideNetworkStakingInfo() {
        do {
            clear(cancellable: &networkInfoCancellable)

            guard let sharedState = sharedState else {
                return
            }
            let chain = selectedChainAsset.chain
            let networkInfoFactory = try sharedState.createNetworkInfoOperationFactory(for: chain)
            let chainId = chain.chainId

            guard
                let runtimeService = chainRegistry.getRuntimeProvider(for: chainId),
                let eraValidatorService = sharedState.eraValidatorService else {
                presenter?.didReceive(error: .networkStakingInfo(ChainRegistryError.runtimeMetadaUnavailable))
                return
            }

            let wrapper = networkInfoFactory.networkStakingOperation(
                for: eraValidatorService,
                runtimeService: runtimeService
            )

            wrapper.targetOperation.completionBlock = { [weak self] in
                DispatchQueue.main.async {
                    guard self?.networkInfoCancellable === wrapper else {
                        return
                    }

                    self?.networkInfoCancellable = nil

                    do {
                        let info = try wrapper.targetOperation.extractNoCancellableResultData()
                        self?.presenter?.didReceive(networkInfo: info)
                    } catch {
                        self?.presenter?.didReceive(error: .networkStakingInfo(error))
                    }
                }
            }

            networkInfoCancellable = wrapper

            operationQueue.addOperations(wrapper.allOperations, waitUntilFinished: false)
        } catch {
            presenter?.didReceive(error: .networkStakingInfo(error))
        }
    }

    private func performMinNominatorBondSubscription() {
        clear(dataProvider: &minNominatorBondProvider)
        minNominatorBondProvider = subscribeToMinNominatorBond(for: selectedChainAsset.chain.chainId)
    }

    private func performBagListSizeSubscription() {
        clear(dataProvider: &bagListSizeProvider)
        bagListSizeProvider = subscribeBagsListSize(for: selectedChainAsset.chain.chainId)
    }

    private func setupState() {
        do {
            let state = try stateFactory.createState()
            sharedState = state
            sharedState?.setupServices()
        } catch {
            presenter?.didReceive(error: .createState(error))
        }
    }

    private func provideEraCompletionTime() {
        do {
            clear(cancellable: &eraCompletionTimeCancellable)
            guard let sharedState = sharedState else {
                return
            }

            let chainId = selectedChainAsset.chain.chainId

            guard let runtimeService = chainRegistry.getRuntimeProvider(for: chainId) else {
                presenter?.didReceive(error: .eraCountdown(ChainRegistryError.runtimeMetadaUnavailable))
                return
            }

            guard let connection = chainRegistry.getConnection(for: chainId) else {
                presenter?.didReceive(error: .eraCountdown(ChainRegistryError.connectionUnavailable))
                return
            }

            let storageRequestFactory = StorageRequestFactory(
                remoteFactory: StorageKeyFactory(),
                operationManager: OperationManager(operationQueue: operationQueue)
            )

            let eraCountdownOperationFactory = try sharedState.createEraCountdownOperationFactory(
                for: selectedChainAsset.chain,
                storageRequestFactory: storageRequestFactory
            )

            let operationWrapper = eraCountdownOperationFactory.fetchCountdownOperationWrapper(
                for: connection,
                runtimeService: runtimeService
            )

            operationWrapper.targetOperation.completionBlock = { [weak self] in
                DispatchQueue.main.async {
                    guard self?.eraCompletionTimeCancellable === operationWrapper else {
                        return
                    }

                    self?.eraCompletionTimeCancellable = nil

                    do {
                        let result = try operationWrapper.targetOperation.extractNoCancellableResultData()
                        self?.presenter?.didReceive(eraCountdown: result)
                    } catch {
                        self?.presenter?.didReceive(error: .eraCountdown(error))
                    }
                }
            }

            eraCompletionTimeCancellable = operationWrapper

            operationQueue.addOperations(operationWrapper.allOperations, waitUntilFinished: false)
        } catch {
            presenter?.didReceive(error: .eraCountdown(error))
        }
    }

    private func provideRewardCalculator() {
        clear(cancellable: &rewardCalculatorCancellable)

        guard let sharedState = sharedState, let calculatorService = sharedState.rewardCalculationService else {
            return
        }

        let operation = calculatorService.fetchCalculatorOperation()

        operation.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                guard self?.rewardCalculatorCancellable === operation else {
                    return
                }
                do {
                    let engine = try operation.extractNoCancellableResultData()
                    self?.presenter?.didReceive(calculator: engine)
                } catch {
                    self?.presenter?.didReceive(error: .calculator(error))
                }
            }
        }

        rewardCalculatorCancellable = operation

        operationQueue.addOperation(operation)
    }

    private func clearAccountRemoteSubscription() {
        stakingAccountUpdatingService.clearSubscription()
    }

    private func performAccountRemoteSubscription() {
        guard let accountId = selectedAccount?.chainAccount.accountId else {
            return
        }

        let chainId = selectedChainAsset.chain.chainId
        let chainFormat = selectedChainAsset.chain.chainFormat

        do {
            try stakingAccountUpdatingService.setupSubscription(
                for: accountId,
                chainId: chainId,
                chainFormat: chainFormat
            )
        } catch {
            presenter?.didReceive(error: .accountRemoteSubscription(error))
        }
    }

    override func setup() {
        super.setup()

        performAccountRemoteSubscription()
        setupState()

        provideRewardCalculator()
        provideNetworkStakingInfo()
        performMinNominatorBondSubscription()
        performBagListSizeSubscription()
        provideEraCompletionTime()
    }
}

extension StartStakingRelaychainInteractor: StakingLocalStorageSubscriber, StakingLocalSubscriptionHandler {
    func handleMinNominatorBond(result: Result<BigUInt?, Error>, chainId _: ChainModel.Id) {
        switch result {
        case let .success(bond):
            presenter?.didReceive(minNominatorBond: bond)
        case let .failure(error):
            presenter?.didReceive(error: .minNominatorBond(error))
        }
    }

    func handleBagListSize(result: Result<UInt32?, Error>, chainId _: ChainModel.Id) {
        switch result {
        case let .success(size):
            presenter?.didReceive(bagListSize: size)
        case let .failure(error):
            presenter?.didReceive(error: .bagListSize(error))
        }
    }
}

extension StartStakingRelaychainInteractor: StartStakingInfoRelaychainInteractorInputProtocol {
    func retryNetworkStakingInfo() {
        provideNetworkStakingInfo()
    }

    func remakeMinNominatorBondSubscription() {
        performMinNominatorBondSubscription()
    }

    func remakeBagListSizeSubscription() {
        performBagListSizeSubscription()
    }

    func retryEraCompletionTime() {
        provideEraCompletionTime()
    }

    func remakeCalculator() {
        provideRewardCalculator()
    }

    func remakeAccountRemoteSubscription() {
        performAccountRemoteSubscription()
    }
}
