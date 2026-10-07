import PrinboxCore
import SwiftUI

/// One line under the header while default repositories are set (spec 4.3): the pins as a pull-down that reopens
/// the picker, and an [x] that clears them. Nothing else.
struct RepositoryStripView: View {
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        if state.hasDefaultRepositories {
            HStack(spacing: 6) {
                RepositoryMenuButton(
                    state: state, actions: actions, title: state.defaultRepositoriesText,
                    help: state.defaultRepositoriesText)
                Spacer()
                IconButton(
                    symbol: "xmark.circle", help: "Clear default repositories", action: actions.clearRepositories)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}
