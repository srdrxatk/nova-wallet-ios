import Foundation
import SoraFoundation
import BigInt

final class SwapSetupPresenter: SwapBasePresenter, PurchaseFlowManaging {
    weak var view: SwapSetupViewProtocol?
    let wireframe: SwapSetupWireframeProtocol
    let interactor: SwapSetupInteractorInputProtocol
    let purchaseProvider: PurchaseProviderProtocol

    private(set) var viewModelFactory: SwapsSetupViewModelFactoryProtocol

    private(set) var quoteArgs: AssetConversion.QuoteArgs? {
        didSet {
            provideDetailsViewModel(isAvailable: quoteArgs != nil)
        }
    }

    private var payAmountInput: AmountInputResult?
    private var receiveAmountInput: Decimal?

    private var canPayFeeInPayAsset: Bool = false
    private var payChainAsset: ChainAsset?
    private var receiveChainAsset: ChainAsset?
    private var feeChainAsset: ChainAsset?

    private var feeIdentifier: SwapSetupFeeIdentifier?
    private var slippage: BigRational?
    private var depositOperations: [DepositOperationModel] = []
    private var purchaseActions: [PurchaseAction] = []
    private var depositCrossChainAssets: [ChainAsset] = []
    private var xcmTransfers: XcmTransfers?

    init(
        payChainAsset: ChainAsset?,
        interactor: SwapSetupInteractorInputProtocol,
        wireframe: SwapSetupWireframeProtocol,
        viewModelFactory: SwapsSetupViewModelFactoryProtocol,
        dataValidatingFactory: SwapDataValidatorFactoryProtocol,
        localizationManager: LocalizationManagerProtocol,
        selectedWallet: MetaAccountModel,
        purchaseProvider: PurchaseProviderProtocol,
        logger: LoggerProtocol
    ) {
        self.payChainAsset = payChainAsset
        feeChainAsset = payChainAsset?.chain.utilityChainAsset()
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.purchaseProvider = purchaseProvider

        super.init(
            selectedWallet: selectedWallet,
            dataValidatingFactory: dataValidatingFactory,
            logger: logger
        )

        self.localizationManager = localizationManager
    }

    private func getPayAmount(for input: AmountInputResult?) -> Decimal? {
        guard let input = input else {
            return nil
        }

        let maxAmount = getMaxModel()?.calculate()
        return input.absoluteValue(from: maxAmount ?? 0)
    }

    private func providePayTitle() {
        let payTitleViewModel = viewModelFactory.payTitleViewModel(
            assetDisplayInfo: payChainAsset?.assetDisplayInfo,
            maxValue: payAssetBalance?.transferable
        )
        view?.didReceiveTitle(payViewModel: payTitleViewModel)
    }

    private func providePayAssetViewModel() {
        let payAssetViewModel = viewModelFactory.payAssetViewModel(chainAsset: payChainAsset)
        view?.didReceiveInputChainAsset(payViewModel: payAssetViewModel)
    }

    private func providePayAmountInputViewModel() {
        guard let payChainAsset = payChainAsset else {
            return
        }
        let amountInputViewModel = viewModelFactory.amountInputViewModel(
            chainAsset: payChainAsset,
            amount: getPayAmount(for: payAmountInput)
        )
        view?.didReceiveAmount(payInputViewModel: amountInputViewModel)
    }

    private func providePayInputPriceViewModel() {
        guard let assetDisplayInfo = payChainAsset?.assetDisplayInfo else {
            view?.didReceiveAmountInputPrice(payViewModel: nil)
            return
        }

        let inputPriceViewModel = viewModelFactory.inputPriceViewModel(
            assetDisplayInfo: assetDisplayInfo,
            amount: getPayAmount(for: payAmountInput),
            priceData: payAssetPriceData
        )

        view?.didReceiveAmountInputPrice(payViewModel: inputPriceViewModel)
    }

    private func provideReceiveTitle() {
        let receiveTitleViewModel = viewModelFactory.receiveTitleViewModel()
        view?.didReceiveTitle(receiveViewModel: receiveTitleViewModel)
    }

    private func provideReceiveAssetViewModel() {
        let receiveAssetViewModel = viewModelFactory.receiveAssetViewModel(
            chainAsset: receiveChainAsset
        )
        view?.didReceiveInputChainAsset(receiveViewModel: receiveAssetViewModel)
    }

    private func provideReceiveAmountInputViewModel() {
        guard let receiveChainAsset = receiveChainAsset else {
            return
        }
        let amountInputViewModel = viewModelFactory.amountInputViewModel(
            chainAsset: receiveChainAsset,
            amount: receiveAmountInput
        )
        view?.didReceiveAmount(receiveInputViewModel: amountInputViewModel)
    }

    private func provideReceiveInputPriceViewModel() {
        guard let assetDisplayInfo = receiveChainAsset?.assetDisplayInfo else {
            view?.didReceiveAmountInputPrice(receiveViewModel: nil)
            return
        }

        let inputPriceViewModel = viewModelFactory.inputPriceViewModel(
            assetDisplayInfo: assetDisplayInfo,
            amount: receiveAmountInput,
            priceData: receiveAssetPriceData
        )

        let differenceViewModel: DifferenceViewModel?
        if let quote = quote, let payAssetDisplayInfo = payChainAsset?.assetDisplayInfo {
            let params = RateParams(
                assetDisplayInfoIn: payAssetDisplayInfo,
                assetDisplayInfoOut: assetDisplayInfo,
                amountIn: quote.amountIn,
                amountOut: quote.amountOut
            )

            differenceViewModel = viewModelFactory.priceDifferenceViewModel(
                rateParams: params,
                priceIn: payAssetPriceData,
                priceOut: receiveAssetPriceData
            )
        } else {
            differenceViewModel = nil
        }

        view?.didReceiveAmountInputPrice(receiveViewModel: .init(
            price: inputPriceViewModel,
            difference: differenceViewModel
        ))
    }

    private func providePayAssetViews() {
        providePayTitle()
        providePayAssetViewModel()
        providePayInputPriceViewModel()
        providePayAmountInputViewModel()
    }

    private func provideReceiveAssetViews() {
        provideReceiveTitle()
        provideReceiveAssetViewModel()
        provideReceiveInputPriceViewModel()
        provideReceiveAmountInputViewModel()
    }

    private func provideButtonState() {
        let buttonState = viewModelFactory.buttonState(
            assetIn: payChainAsset?.chainAssetId,
            assetOut: receiveChainAsset?.chainAssetId,
            amountIn: getPayAmount(for: payAmountInput),
            amountOut: receiveAmountInput
        )

        view?.didReceiveButtonState(
            title: buttonState.title.value(for: selectedLocale),
            enabled: buttonState.enabled
        )
    }

    private func provideSettingsState() {
        view?.didReceiveSettingsState(isAvailable: payChainAsset != nil)
    }

    private func provideDetailsViewModel(isAvailable: Bool) {
        view?.didReceiveDetailsState(isAvailable: isAvailable)
    }

    private func provideRateViewModel() {
        guard
            let assetDisplayInfoIn = payChainAsset?.assetDisplayInfo,
            let assetDisplayInfoOut = receiveChainAsset?.assetDisplayInfo,
            let quote = quote else {
            view?.didReceiveRate(viewModel: .loading)
            return
        }
        let rateViewModel = viewModelFactory.rateViewModel(from: .init(
            assetDisplayInfoIn: assetDisplayInfoIn,
            assetDisplayInfoOut: assetDisplayInfoOut,
            amountIn: quote.amountIn,
            amountOut: quote.amountOut
        ))

        view?.didReceiveRate(viewModel: .loaded(value: rateViewModel))
    }

    private func provideFeeViewModel() {
        guard quoteArgs != nil, let feeChainAsset = feeChainAsset else {
            return
        }
        guard let fee = fee?.networkFee.targetAmount else {
            view?.didReceiveNetworkFee(viewModel: .loading)
            return
        }
        let isEditable = (payChainAsset?.isUtilityAsset == false) && canPayFeeInPayAsset
        let viewModel = viewModelFactory.feeViewModel(
            amount: fee,
            assetDisplayInfo: feeChainAsset.assetDisplayInfo,
            isEditable: isEditable,
            priceData: feeAssetPriceData
        )

        view?.didReceiveNetworkFee(viewModel: .loaded(value: viewModel))
    }

    private func provideIssues() {
        var issues: [SwapSetupViewIssue] = []

        if
            let balance = payAssetBalance?.transferable,
            balance == 0 {
            issues.append(.zeroBalance)
        }

        if
            let payAmount = getPayAmount(for: payAmountInput),
            let maxAmount = getMaxModel()?.calculate(),
            payAmount > maxAmount {
            issues.append(.insufficientToken)
        }

        view?.didReceive(issues: issues)
    }

    func refreshQuote(direction: AssetConversion.Direction, forceUpdate: Bool = true) {
        guard
            let payChainAsset = payChainAsset,
            let receiveChainAsset = receiveChainAsset else {
            return
        }

        if forceUpdate {
            quote = nil
        }

        switch direction {
        case .buy:
            refreshQuoteForBuy(
                payChainAsset: payChainAsset,
                receiveChainAsset: receiveChainAsset,
                forceUpdate: forceUpdate
            )
        case .sell:
            refreshQuoteForSell(
                payChainAsset: payChainAsset,
                receiveChainAsset: receiveChainAsset,
                forceUpdate: forceUpdate
            )
        }

        provideRateViewModel()
        provideFeeViewModel()
    }

    private func refreshQuoteForBuy(payChainAsset: ChainAsset, receiveChainAsset: ChainAsset, forceUpdate: Bool) {
        if
            let receiveInPlank = receiveAmountInput?.toSubstrateAmount(
                precision: receiveChainAsset.assetDisplayInfo.assetPrecision
            ),
            receiveInPlank > 0 {
            let quoteArgs = AssetConversion.QuoteArgs(
                assetIn: payChainAsset.chainAssetId,
                assetOut: receiveChainAsset.chainAssetId,
                amount: receiveInPlank,
                direction: .buy
            )
            self.quoteArgs = quoteArgs
            interactor.calculateQuote(for: quoteArgs)
        } else {
            quoteArgs = nil
            if forceUpdate {
                payAmountInput = nil
                providePayAmountInputViewModel()
            } else {
                refreshQuote(direction: .sell)
            }
        }
    }

    private func refreshQuoteForSell(payChainAsset: ChainAsset, receiveChainAsset: ChainAsset, forceUpdate: Bool) {
        if let payInPlank = getPayAmount(for: payAmountInput)?.toSubstrateAmount(
            precision: Int16(payChainAsset.assetDisplayInfo.assetPrecision)), payInPlank > 0 {
            let quoteArgs = AssetConversion.QuoteArgs(
                assetIn: payChainAsset.chainAssetId,
                assetOut: receiveChainAsset.chainAssetId,
                amount: payInPlank,
                direction: .sell
            )
            self.quoteArgs = quoteArgs
            interactor.calculateQuote(for: quoteArgs)
        } else {
            quoteArgs = nil
            if forceUpdate {
                receiveAmountInput = nil
                provideReceiveAmountInputViewModel()
                provideReceiveInputPriceViewModel()
            } else {
                refreshQuote(direction: .buy)
            }
        }
    }

    private func updateFeeChainAsset(_ chainAsset: ChainAsset?) {
        feeChainAsset = chainAsset
        providePayAssetViews()
        interactor.update(feeChainAsset: chainAsset)

        fee = nil
        provideFeeViewModel()

        estimateFee()
    }

    // MARK: Base implementation

    override func getInputAmount() -> Decimal? {
        guard let payAmountInput = payAmountInput else {
            return nil
        }

        let maxAmount = getMaxModel()?.calculate() ?? 0
        return payAmountInput.absoluteValue(from: maxAmount)
    }

    override func getPayChainAsset() -> ChainAsset? {
        payChainAsset
    }

    override func getReceiveChainAsset() -> ChainAsset? {
        receiveChainAsset
    }

    override func getFeeChainAsset() -> ChainAsset? {
        feeChainAsset
    }

    override func getQuoteArgs() -> AssetConversion.QuoteArgs? {
        quoteArgs
    }

    override func getSlippage() -> BigRational? {
        slippage
    }

    override func shouldHandleQuote(for args: AssetConversion.QuoteArgs?) -> Bool {
        quoteArgs == args
    }

    override func shouldHandleFee(for feeIdentifier: TransactionFeeId, feeChainAssetId: ChainAssetId?) -> Bool {
        self.feeIdentifier == SwapSetupFeeIdentifier(transactionId: feeIdentifier, feeChainAssetId: feeChainAssetId)
    }

    override func estimateFee() {
        guard let quote = quote,
              let receiveChain = receiveChainAsset?.chain,
              let accountId = selectedWallet.fetch(for: receiveChain.accountRequest())?.accountId,
              let quoteArgs = quoteArgs,
              let slippage = slippage else {
            return
        }

        let args = AssetConversion.CallArgs(
            assetIn: quote.assetIn,
            amountIn: quote.amountIn,
            assetOut: quote.assetOut,
            amountOut: quote.amountOut,
            receiver: accountId,
            direction: quoteArgs.direction,
            slippage: slippage
        )

        let newIdentifier = SwapSetupFeeIdentifier(
            transactionId: args.identifier,
            feeChainAssetId: feeChainAsset?.chainAssetId
        )

        guard newIdentifier != feeIdentifier else {
            return
        }

        feeIdentifier = newIdentifier
        interactor.calculateFee(args: args)
    }

    override func applySwapMax() {
        payAmountInput = .rate(1)
        providePayAssetViews()
        refreshQuote(direction: .sell)
        provideButtonState()
        provideIssues()
    }

    override func handleBaseError(_ error: SwapBaseError) {
        handleBaseError(
            error,
            view: view,
            interactor: interactor,
            wireframe: wireframe,
            locale: selectedLocale
        )
    }

    override func handleNewQuote(_ quote: AssetConversion.Quote, for quoteArgs: AssetConversion.QuoteArgs) {
        logger.debug("New quote: \(quote)")

        switch quoteArgs.direction {
        case .buy:
            let payAmount = payChainAsset.map {
                Decimal.fromSubstrateAmount(
                    quote.amountIn,
                    precision: Int16($0.asset.precision)
                ) ?? 0
            }
            payAmountInput = payAmount.map { .absolute($0) }
            providePayAmountInputViewModel()
        case .sell:
            receiveAmountInput = receiveChainAsset.map {
                Decimal.fromSubstrateAmount(
                    quote.amountOut,
                    precision: $0.asset.displayInfo.assetPrecision
                ) ?? 0
            }
            provideReceiveAmountInputViewModel()
            provideReceiveInputPriceViewModel()
        }

        provideRateViewModel()
        provideButtonState()

        estimateFee()
    }

    override func handleNewFee(
        _: AssetConversion.FeeModel?,
        transactionFeeId _: TransactionFeeId,
        feeChainAssetId _: ChainAssetId?
    ) {
        provideFeeViewModel()

        if case .rate = payAmountInput {
            providePayInputPriceViewModel()
            providePayAmountInputViewModel()
        }

        provideButtonState()
        provideIssues()
    }

    override func handleNewPrice(_: PriceData?, chainAssetId: ChainAssetId) {
        if payChainAsset?.chainAssetId == chainAssetId {
            providePayInputPriceViewModel()
        }

        if receiveChainAsset?.chainAssetId == chainAssetId {
            provideReceiveInputPriceViewModel()
        }

        if feeChainAsset?.chainAssetId == chainAssetId {
            provideFeeViewModel()
        }
    }

    override func handleNewBalance(_: AssetBalance?, for chainAsset: ChainAssetId) {
        if payChainAsset?.chainAssetId == chainAsset {
            providePayTitle()
            provideIssues()

            if case .rate = payAmountInput {
                providePayInputPriceViewModel()
                providePayAmountInputViewModel()
                provideButtonState()
            }
        }
    }

    override func handleNewBalanceExistense(_: AssetBalanceExistence, chainAssetId _: ChainAssetId) {
        if case .rate = payAmountInput {
            providePayInputPriceViewModel()
            providePayAmountInputViewModel()
            provideButtonState()
        }
    }

    override func handleNewAccountInfo(_: AccountInfo?, chainId _: ChainModel.Id) {
        if case .rate = payAmountInput {
            providePayInputPriceViewModel()
            providePayAmountInputViewModel()
            provideButtonState()
        }
    }
}

extension SwapSetupPresenter: SwapSetupPresenterProtocol {
    func setup() {
        providePayAssetViews()
        provideReceiveAssetViews()
        provideDetailsViewModel(isAvailable: false)
        provideButtonState()
        provideSettingsState()
        // TODO: get from settings
        slippage = .fraction(from: AssetConversionConstants.defaultSlippage)?.fromPercents()
        provideIssues()

        interactor.setup()
        interactor.update(payChainAsset: payChainAsset)
        interactor.update(feeChainAsset: feeChainAsset)
    }

    func selectPayToken() {
        wireframe.showPayTokenSelection(from: view, chainAsset: receiveChainAsset) { [weak self] chainAsset in
            self?.payChainAsset = chainAsset
            let feeChainAsset = chainAsset.chain.utilityAsset().map {
                ChainAsset(chain: chainAsset.chain, asset: $0)
            }

            self?.feeChainAsset = feeChainAsset
            self?.fee = nil
            self?.canPayFeeInPayAsset = false

            self?.providePayAssetViews()
            self?.provideButtonState()
            self?.provideSettingsState()
            self?.provideFeeViewModel()
            self?.provideIssues()

            self?.interactor.update(payChainAsset: chainAsset)
            self?.interactor.update(feeChainAsset: feeChainAsset)

            if let direction = self?.quoteArgs?.direction {
                self?.refreshQuote(direction: direction, forceUpdate: false)
            } else if self?.payAmountInput != nil {
                self?.refreshQuote(direction: .sell, forceUpdate: false)
            } else {
                self?.refreshQuote(direction: .buy, forceUpdate: false)
            }
        }
    }

    func selectReceiveToken() {
        wireframe.showReceiveTokenSelection(from: view, chainAsset: payChainAsset) { [weak self] chainAsset in
            self?.receiveChainAsset = chainAsset
            self?.provideReceiveAssetViews()
            self?.provideButtonState()

            self?.interactor.update(receiveChainAsset: chainAsset)

            if let direction = self?.quoteArgs?.direction {
                self?.refreshQuote(direction: direction, forceUpdate: false)
            } else if self?.receiveAmountInput != nil {
                self?.refreshQuote(direction: .buy, forceUpdate: false)
            } else {
                self?.refreshQuote(direction: .sell, forceUpdate: false)
            }
        }
    }

    func updatePayAmount(_ amount: Decimal?) {
        payAmountInput = amount.map { .absolute($0) }
        refreshQuote(direction: .sell)
        provideButtonState()
        provideIssues()
    }

    func updateReceiveAmount(_ amount: Decimal?) {
        receiveAmountInput = amount
        refreshQuote(direction: .buy)
        provideButtonState()
        provideIssues()
    }

    func flip(currentFocus: TextFieldFocus?) {
        let payAmount = getPayAmount(for: payAmountInput)
        let receiveAmount = receiveAmountInput.map { AmountInputResult.absolute($0) }

        Swift.swap(&payChainAsset, &receiveChainAsset)
        canPayFeeInPayAsset = false

        interactor.update(payChainAsset: payChainAsset)
        interactor.update(receiveChainAsset: receiveChainAsset)
        let newFocus: TextFieldFocus?

        switch currentFocus {
        case .payAsset:
            newFocus = .receiveAsset
        case .receiveAsset:
            newFocus = .payAsset
        case .none:
            newFocus = nil
        }

        switch quoteArgs?.direction {
        case .sell:
            receiveAmountInput = payAmount
            payAmountInput = nil
            refreshQuote(direction: .buy, forceUpdate: false)
        case .buy:
            payAmountInput = receiveAmount
            receiveAmountInput = nil
            refreshQuote(direction: .sell, forceUpdate: false)
        case .none:
            payAmountInput = nil
            receiveAmountInput = nil
        }

        providePayAssetViews()
        provideReceiveAssetViews()
        provideButtonState()
        provideSettingsState()
        provideFeeViewModel()
        provideIssues()

        view?.didReceive(focus: newFocus)
    }

    func selectMaxPayAmount() {
        applySwapMax()
    }

    func showFeeActions() {
        guard let payChainAsset = payChainAsset,
              let utilityAsset = payChainAsset.chain.utilityChainAsset() else {
            return
        }
        let payAssetSelected = feeChainAsset?.chainAssetId == payChainAsset.chainAssetId
        let viewModel = SwapNetworkFeeSheetViewModel(
            title: FeeSelectionViewModel.title,
            message: FeeSelectionViewModel.message,
            sectionTitle: { section in
                .init { _ in
                    FeeSelectionViewModel(rawValue: section) == .utilityAsset ?
                        utilityAsset.asset.symbol : payChainAsset.asset.symbol
                }
            },
            action: { [weak self] in
                let chainAsset = FeeSelectionViewModel(rawValue: $0) == .utilityAsset ? utilityAsset : payChainAsset
                self?.updateFeeChainAsset(chainAsset)
            },
            selectedIndex: payAssetSelected ? FeeSelectionViewModel.payAsset.rawValue :
                FeeSelectionViewModel.utilityAsset.rawValue,
            count: FeeSelectionViewModel.allCases.count,
            hint: FeeSelectionViewModel.hint
        )

        wireframe.showNetworkFeeAssetSelection(
            form: view,
            viewModel: viewModel
        )
    }

    func showFeeInfo() {
        wireframe.showFeeInfo(from: view)
    }

    func showRateInfo() {
        wireframe.showRateInfo(from: view)
    }

    func proceed() {
        guard let swapModel = getSwapModel() else {
            return
        }

        let validators = getBaseValidations(for: swapModel, interactor: interactor, locale: selectedLocale)

        DataValidationRunner(validators: validators).runValidation { [weak self] in
            guard let slippage = self?.slippage,
                  let quote = self?.quote,
                  let quoteArgs = self?.quoteArgs else {
                return
            }

            let confirmInitState = SwapConfirmInitState(
                chainAssetIn: swapModel.payChainAsset,
                chainAssetOut: swapModel.receiveChainAsset,
                feeChainAsset: swapModel.feeChainAsset,
                slippage: slippage,
                quote: quote,
                quoteArgs: quoteArgs
            )

            self?.wireframe.showConfirmation(
                from: self?.view,
                initState: confirmInitState
            )
        }
    }

    func showSettings() {
        guard let payChainAsset = payChainAsset else {
            return
        }
        wireframe.showSettings(
            from: view,
            percent: slippage,
            chainAsset: payChainAsset
        ) { [weak self, payChainAsset] slippageValue in
            guard payChainAsset.chainAssetId == self?.payChainAsset?.chainAssetId else {
                return
            }
            self?.slippage = slippageValue
            self?.estimateFee()
        }
    }

    func depositInsufficientToken() {
        guard
            let payChainAsset = payChainAsset,
            let accountId = selectedWallet.fetch(for: payChainAsset.chain.accountRequest())?.accountId else {
            return
        }

        purchaseActions = purchaseProvider.buildPurchaseActions(for: payChainAsset, accountId: accountId)
        let sendAvailable = TokenOperation.checkTransferOperationAvailable()
        let crossChainSendAvailable = depositCrossChainAssets.first != nil && sendAvailable

        let recieveAvailable = TokenOperation.checkReceiveOperationAvailable(
            walletType: selectedWallet.type,
            chainAsset: payChainAsset
        ).available
        let buyAvailable = TokenOperation.checkBuyOperationAvailable(
            purchaseActions: purchaseActions,
            walletType: selectedWallet.type,
            chainAsset: payChainAsset
        ).available
        depositOperations = [
            .init(operation: .send, active: crossChainSendAvailable),
            .init(operation: .receive, active: recieveAvailable),
            .init(operation: .buy, active: buyAvailable)
        ]
        wireframe.showTokenDepositOptions(
            form: view,
            operations: depositOperations,
            token: payChainAsset.asset.symbol,
            delegate: self
        )
    }
}

extension SwapSetupPresenter: SwapSetupInteractorOutputProtocol {
    func didReceive(setupError: SwapSetupError) {
        logger.error("Did receive setup error: \(setupError)")

        switch setupError {
        case .payAssetSetFailed:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                if let payChainAsset = self?.payChainAsset {
                    self?.interactor.update(payChainAsset: payChainAsset)
                }
            }
        case .xcm:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.interactor.setupXcm()
            }
        case .blockNumber:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.interactor.retryBlockNumberSubscription()
            }
        case .remoteSubscription:
            wireframe.presentRequestStatus(on: view, locale: selectedLocale) { [weak self] in
                self?.interactor.retryRemoteSubscription()
            }
        }
    }

    func didReceiveCanPayFeeInPayAsset(_ value: Bool, chainAssetId: ChainAssetId) {
        if payChainAsset?.chainAssetId == chainAssetId {
            canPayFeeInPayAsset = value

            provideFeeViewModel()
        }
    }

    func didReceiveAvailableXcm(origins: [ChainAsset], xcmTransfers: XcmTransfers?) {
        depositCrossChainAssets = origins
        self.xcmTransfers = xcmTransfers
    }

    func didReceiveBlockNumber(_ blockNumber: BlockNumber?, chainId _: ChainModel.Id) {
        logger.debug("New block number: \(String(describing: blockNumber))")

        refreshQuote(direction: quoteArgs?.direction ?? .sell, forceUpdate: false)
        estimateFee()
    }
}

extension SwapSetupPresenter: Localizable {
    func applyLocalization() {
        if view?.isSetup == true {
            setup()
            viewModelFactory.locale = selectedLocale
        }
    }
}

extension SwapSetupPresenter: ModalPickerViewControllerDelegate {
    func modalPickerDidSelectModelAtIndex(_ index: Int, context _: AnyObject?) {
        guard let operation = depositOperations[safe: index], operation.active else {
            return
        }

        switch operation.operation {
        case .buy:
            startPuchaseFlow(
                from: view,
                purchaseActions: purchaseActions,
                wireframe: wireframe,
                locale: selectedLocale
            )
        case .receive:
            guard let payChainAsset = payChainAsset,
                  let metaChainAccountResponse = selectedWallet.fetchMetaChainAccount(
                      for: payChainAsset.chain.accountRequest()
                  ) else {
                return
            }
            wireframe.showDepositTokensByReceive(
                from: view,
                chainAsset: payChainAsset,
                metaChainAccountResponse: metaChainAccountResponse
            )
        case .send:
            guard let payChainAsset = payChainAsset,
                  let accountId = selectedWallet.fetch(for: payChainAsset.chain.accountRequest()),
                  let address = accountId.toAddress(),
                  let origin = depositCrossChainAssets.first,
                  let xcmTransfers = xcmTransfers else {
                return
            }

            wireframe.showDepositTokensBySend(
                from: view,
                origin: origin,
                destination: payChainAsset,
                recepient: .init(address: address, username: ""),
                xcmTransfers: xcmTransfers
            )
        }
    }
}

extension SwapSetupPresenter: PurchaseDelegate {
    func purchaseDidComplete() {
        wireframe.presentPurchaseDidComplete(view: view, locale: selectedLocale)
    }
}
