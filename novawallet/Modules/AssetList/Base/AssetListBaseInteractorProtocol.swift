import Foundation
import RobinHood
import BigInt

protocol AssetListBaseInteractorInputProtocol: AnyObject {
    func setup()
}

protocol AssetListBaseInteractorOutputProtocol: AnyObject {
    func didReceiveChainModelChanges(_ changes: [DataProviderChange<ChainModel>])
    func didReceiveBalance(results: [ChainAssetId: Result<CalculatedAssetBalance?, Error>])
    func didReceiveCrowdloans(result: Result<[ChainModel.Id: [CrowdloanContributionData]], Error>)
    func didReceivePrices(result: Result<[ChainAssetId: PriceData], Error>?)
}
