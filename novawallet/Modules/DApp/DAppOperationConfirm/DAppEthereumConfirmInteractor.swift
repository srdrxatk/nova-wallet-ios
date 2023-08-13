import Foundation
import BigInt
import RobinHood
import SwiftRLP
import SubstrateSdk

final class DAppEthereumConfirmInteractor: DAppOperationBaseInteractor {
    let request: DAppOperationRequest
    let ethereumOperationFactory: EthereumOperationFactoryProtocol
    let operationQueue: OperationQueue
    let signingWrapperFactory: SigningWrapperFactoryProtocol
    let shouldSendTransaction: Bool
    let chainId: String

    private var transaction: EthereumTransaction?
    private var ethereumService: EvmTransactionServiceProtocol?
    private var signingWrapper: SigningWrapperProtocol?

    init(
        chainId: String,
        request: DAppOperationRequest,
        ethereumOperationFactory: EthereumOperationFactoryProtocol,
        operationQueue: OperationQueue,
        signingWrapperFactory: SigningWrapperFactoryProtocol,
        shouldSendTransaction: Bool
    ) {
        self.chainId = chainId
        self.request = request
        self.ethereumOperationFactory = ethereumOperationFactory
        self.operationQueue = operationQueue
        self.signingWrapperFactory = signingWrapperFactory
        self.shouldSendTransaction = shouldSendTransaction
    }

    private func setupServices() {
        let optTransaction = try? request.operationData.map(to: EthereumTransaction.self)

        guard let transaction = optTransaction else {
            let error = DAppOperationConfirmInteractorError.extrinsicBadField(name: "root")
            presenter?.didReceive(modelResult: .failure(error))
            return
        }

        self.transaction = transaction

        guard
            let transaction = try? request.operationData.map(to: EthereumTransaction.self),
            let chainAccountId = try? AccountId(hexString: transaction.from),
            let accountResponse = request.wallet.fetchEthereum(for: chainAccountId) else {
            presenter?.didReceive(modelResult: .failure(ChainAccountFetchingError.accountNotExists))
            return
        }

        let gasPriceProvider = createGasPriceProvider(for: transaction)
        let gasLimitProvider = createGasLimitProvider(for: transaction)
        let nonceProvider = createNonceProvider(for: transaction)

        ethereumService = EvmTransactionService(
            accountId: chainAccountId,
            operationFactory: ethereumOperationFactory,
            gasPriceProvider: gasPriceProvider,
            gasLimitProvider: gasLimitProvider,
            nonceProvider: nonceProvider,
            chainFormat: .ethereum,
            evmChainId: chainId,
            operationQueue: operationQueue
        )

        signingWrapper = signingWrapperFactory.createSigningWrapper(for: accountResponse)
    }

    private func createBuilderClosure(for transaction: EthereumTransaction) -> EvmTransactionBuilderClosure {
        { builder in

            var currentBuilder = builder

            if let dataHex = transaction.data {
                guard let data = try? Data(hexString: dataHex) else {
                    throw DAppOperationConfirmInteractorError.extrinsicBadField(name: "data")
                }

                currentBuilder = currentBuilder.usingTransactionData(data)
            }

            if let value = transaction.value {
                guard let valueInt = BigUInt.fromHexString(value) else {
                    throw DAppOperationConfirmInteractorError.extrinsicBadField(name: "value")
                }

                currentBuilder = currentBuilder.sendingValue(valueInt)
            }

            if let receiver = transaction.to {
                currentBuilder = currentBuilder.toAddress(receiver)
            }

            return currentBuilder
        }
    }

    private func createGasLimitProvider(for transaction: EthereumTransaction) -> EvmGasLimitProviderProtocol {
        if let gasLimit = transaction.gas, let value = try? BigUInt(hex: gasLimit), value > 0 {
            return EvmConstantGasLimitProvider(value: value)
        } else {
            return EvmDefaultGasLimitProvider(operationFactory: ethereumOperationFactory)
        }
    }

    private func createGasPriceProvider(for transaction: EthereumTransaction) -> EvmGasPriceProviderProtocol {
        if let gasPrice = transaction.gasPrice, let value = try? BigUInt(hex: gasPrice), value > 0 {
            return EvmConstantGasPriceProvider(value: value)
        } else {
            return EvmLegacyGasPriceProvider(operationFactory: ethereumOperationFactory)
        }
    }

    private func createNonceProvider(for transaction: EthereumTransaction) -> EvmNonceProviderProtocol {
        if let nonce = transaction.nonce, let value = BigUInt.fromHexString(nonce) {
            return EvmConstantNonceProvider(value: value)
        } else {
            return EvmDefaultNonceProvider(operationFactory: ethereumOperationFactory)
        }
    }

    private func provideConfirmationModel(for transaction: EthereumTransaction) {
        guard let chainAccountId = try? Data(hexString: transaction.from) else {
            presenter?.didReceive(feeResult: .failure(ChainAccountFetchingError.accountNotExists))
            return
        }

        let model = DAppOperationConfirmModel(
            accountName: request.wallet.name,
            walletIdenticon: request.wallet.walletIdenticonData(),
            chainAccountId: chainAccountId,
            chainAddress: transaction.from,
            dApp: request.dApp,
            dAppIcon: request.dAppIcon
        )

        presenter?.didReceive(modelResult: .success(model))
    }

    private func provideFeeModel(
        for transaction: EthereumTransaction,
        service: EvmTransactionServiceProtocol
    ) {
        service.estimateFee(createBuilderClosure(for: transaction), runningIn: .main) { [weak self] result in
            switch result {
            case let .success(fee):
                let dispatchInfo = RuntimeDispatchInfo(
                    fee: String(fee),
                    weight: 0
                )

                self?.presenter?.didReceive(feeResult: .success(dispatchInfo))
            case let .failure(error):
                self?.presenter?.didReceive(feeResult: .failure(error))
            }
        }
    }

    private func confirmSend(
        for transaction: EthereumTransaction,
        service: EvmTransactionServiceProtocol,
        signer: SigningWrapperProtocol
    ) {
        service.submit(
            createBuilderClosure(for: transaction),
            signer: signer,
            runningIn: .main
        ) { [weak self] result in
            guard let self = self else {
                return
            }

            do {
                switch result {
                case let .success(txHash):
                    let txHashData = try Data(hexString: txHash)
                    let response = DAppOperationResponse(signature: txHashData)
                    let result: Result<DAppOperationResponse, Error> = .success(response)
                    self.presenter?.didReceive(responseResult: result, for: self.request)
                case let .failure(error):
                    throw error
                }
            } catch {
                let result: Result<DAppOperationResponse, Error> = .failure(error)
                self.presenter?.didReceive(responseResult: result, for: self.request)
            }
        }
    }

    private func confirmSign(
        for transaction: EthereumTransaction,
        service: EvmTransactionServiceProtocol,
        signer: SigningWrapperProtocol
    ) {
        service.sign(
            createBuilderClosure(for: transaction),
            signer: signer,
            runningIn: .main
        ) { [weak self] result in
            guard let self = self else {
                return
            }

            do {
                switch result {
                case let .success(signedTransaction):
                    let response = DAppOperationResponse(signature: signedTransaction)
                    let result: Result<DAppOperationResponse, Error> = .success(response)
                    self.presenter?.didReceive(responseResult: result, for: self.request)
                case let .failure(error):
                    throw error
                }
            } catch {
                let result: Result<DAppOperationResponse, Error> = .failure(error)
                self.presenter?.didReceive(responseResult: result, for: self.request)
            }
        }
    }
}

extension DAppEthereumConfirmInteractor: DAppOperationConfirmInteractorInputProtocol {
    func setup() {
        setupServices()

        guard
            let transaction = transaction,
            let ethereumService = ethereumService else {
            return
        }

        provideConfirmationModel(for: transaction)
        provideFeeModel(for: transaction, service: ethereumService)
    }

    func estimateFee() {
        guard
            let transaction = transaction,
            let ethereumService = ethereumService else {
            return
        }

        provideFeeModel(for: transaction, service: ethereumService)
    }

    func confirm() {
        guard
            let transaction = transaction,
            let ethereumService = ethereumService,
            let signer = signingWrapper else {
            return
        }

        if shouldSendTransaction {
            confirmSend(for: transaction, service: ethereumService, signer: signer)
        } else {
            confirmSign(for: transaction, service: ethereumService, signer: signer)
        }
    }

    func reject() {
        let response = DAppOperationResponse(signature: nil)
        presenter?.didReceive(responseResult: .success(response), for: request)
    }

    func prepareTxDetails() {
        presenter?.didReceive(txDetailsResult: .success(request.operationData))
    }
}
