import Foundation

struct XcmAssetTransferFee {
    enum FeeType: String, Decodable {
        case proportional
        case standard
    }

    struct Mode: Decodable {
        let type: XcmAssetTransferFee.FeeType
        let coefficient: String?
    }

    let mode: XcmAssetTransferFee.Mode
    let instructions: [String]
}
