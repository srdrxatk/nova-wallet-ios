import Foundation
import BigInt
import SubstrateSdk

extension Xcm {
    static let ormlTransferCallName = "transfer_multiasset"

    struct OrmlTransferCallV1: Codable {
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case asset
            case destination = "dest"
            case destinationWeight = "dest_weight"
        }

        let asset: VersionedMultiasset
        let destination: VersionedMultilocation

        // must be set as maximum between reserve and destination
        @StringCodable var destinationWeight: BigUInt

        func runtimeCall(for module: String) -> RuntimeCall<Self> {
            RuntimeCall(moduleName: module, callName: Xcm.ormlTransferCallName, args: self)
        }

        func codingPath(for module: String) -> CallCodingPath {
            CallCodingPath(moduleName: module, callName: Xcm.ormlTransferCallName)
        }
    }

    struct OrmlTransferCallV2: Codable {
        // swiftlint:disable:next nesting
        enum CodingKeys: String, CodingKey {
            case asset
            case destination = "dest"
            case destinationWeightLimit = "dest_weight_limit"
        }

        static let callName = "transfer_multiasset"

        let asset: VersionedMultiasset
        let destination: VersionedMultilocation

        // must be set as maximum between reserve and destination
        let destinationWeightLimit: Xcm.WeightLimit<JSON>

        func runtimeCall(for module: String) -> RuntimeCall<Self> {
            RuntimeCall(moduleName: module, callName: Xcm.ormlTransferCallName, args: self)
        }

        func codingPath(for module: String) -> CallCodingPath {
            CallCodingPath(moduleName: module, callName: Xcm.ormlTransferCallName)
        }
    }

    static func appendOrmlTransferCall(
        asset: VersionedMultiasset,
        destination: VersionedMultilocation,
        weight: BigUInt,
        module: String,
        codingFactory: RuntimeCoderFactoryProtocol
    ) throws -> (ExtrinsicBuilderClosure, CallCodingPath) {
        let path = CallCodingPath(moduleName: module, callName: Xcm.ormlTransferCallName)

        guard let callType = codingFactory.getCall(for: path) else {
            return ({ $0 }, path)
        }

        let paramNameV1 = OrmlTransferCallV1.CodingKeys.destinationWeight.rawValue

        // v1 require only uint64 weight and v2 requires weight limit
        let isV1 = callType.isArgumentTypeOf(paramNameV1) { argumentType in
            codingFactory.isUInt64Type(argumentType)
        }

        if isV1 {
            let call = OrmlTransferCallV1(asset: asset, destination: destination, destinationWeight: weight)

            return ({ try $0.adding(call: call.runtimeCall(for: module)) }, path)
        } else {
            let paramNameV2 = OrmlTransferCallV2.CodingKeys.destinationWeightLimit.rawValue

            let optWeightJson = try BlockchainWeightFactory.convertCallVersionedWeightInWeightLimitToJson(
                for: .init(path: path, argName: paramNameV2),
                codingFactory: codingFactory,
                weight: UInt64(weight)
            )

            guard let weightJson = optWeightJson else {
                throw XcmTransferServiceError.noArgumentFound(paramNameV2)
            }

            let call = OrmlTransferCallV2(
                asset: asset,
                destination: destination,
                destinationWeightLimit: .limited(weight: weightJson)
            )

            return ({ try $0.adding(call: call.runtimeCall(for: module)) }, path)
        }
    }
}
