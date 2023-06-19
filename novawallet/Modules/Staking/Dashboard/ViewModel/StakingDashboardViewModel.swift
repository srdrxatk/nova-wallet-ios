import Foundation

struct StakingDashboardEnabledViewModel {
    enum Status {
        case active
        case inactive
        case waiting

        init(dashboardItem: Multistaking.DashboardItem) {
            guard dashboardItem.stake != nil else {
                self = .inactive
                return
            }

            switch dashboardItem.state {
            case .active:
                self = .active
            case .waiting:
                self = .waiting
            case .inactive, .none:
                self = .inactive
            }
        }
    }

    let networkViewModel: LoadableViewModelState<NetworkViewModel>
    let totalRewards: LoadableViewModelState<BalanceViewModelProtocol>
    let status: LoadableViewModelState<Status>
    let yourStake: LoadableViewModelState<BalanceViewModelProtocol>
    let estimatedEarnings: LoadableViewModelState<String>
}

struct StakingDashboardDisabledViewModel {
    let networkViewModel: LoadableViewModelState<NetworkViewModel>
    let estimatedEarnings: LoadableViewModelState<String>
    let balance: String?
}

struct StakingDashboardViewModel {
    let active: [StakingDashboardEnabledViewModel]
    let inactive: [StakingDashboardDisabledViewModel]
    let hasMoreOptions: Bool
    let isSyncing: Bool
}
