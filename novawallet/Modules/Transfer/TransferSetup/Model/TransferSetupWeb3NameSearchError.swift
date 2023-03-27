import SoraFoundation

enum TransferSetupWeb3NameSearchError: Error {
    case accountNotFound(String)
    case serviceNotFound(String)
    case coinsListIsEmpty
    case kiltService(Error)
}

extension TransferSetupWeb3NameSearchError: ErrorContentConvertible {
    func toErrorContent(for locale: Locale?) -> ErrorContent {
        let title: String
        let message: String
        let strings = R.string.localizable.self

        switch self {
        case let .accountNotFound(name):
            title = strings.transferSetupErrorW3nAccountNotFoundTitle(preferredLanguages: locale?.rLanguages)
            message = strings.transferSetupErrorW3nAccountNotFoundSubtitle(
                name,
                preferredLanguages: locale?.rLanguages
            )
        case let .serviceNotFound(name):
            title = strings.transferSetupErrorW3nServiceNotFoundTitle(preferredLanguages: locale?.rLanguages)
            message = strings.transferSetupErrorW3nServiceNotFoundSubtitle(
                name,
                preferredLanguages: locale?.rLanguages
            )
        default:
            title = strings.transferSetupErrorW3nKiltServiceUnavailableTitle(preferredLanguages: locale?.rLanguages)
            message = strings.transferSetupErrorW3nKiltServiceUnavailableSubtitle(
                preferredLanguages: locale?.rLanguages)
        }

        return ErrorContent(title: title, message: message)
    }
}
