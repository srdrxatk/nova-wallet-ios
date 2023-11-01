import BigInt

protocol SwapBaseInteractorInputProtocol: AnyObject {
    func setup()
    func calculateQuote(for args: AssetConversion.QuoteArgs)
    func calculateFee(args: AssetConversion.CallArgs)
    func remakePriceSubscription(for chainAsset: ChainAsset)
}

protocol SwapBaseInteractorOutputProtocol: AnyObject {
    func didReceive(quote: AssetConversion.Quote, for quoteArgs: AssetConversion.QuoteArgs)
    func didReceive(fee: AssetConversion.FeeModel?, transactionId: TransactionFeeId, feeChainAssetId: ChainAssetId?)
    func didReceive(baseError: SwapSetupError)
    func didReceive(price: PriceData?, priceId: AssetModel.PriceId)
    func didReceive(payAccountId: AccountId?)
    func didReceive(balance: AssetBalance?, for chainAsset: ChainAssetId, accountId: AccountId)
}
