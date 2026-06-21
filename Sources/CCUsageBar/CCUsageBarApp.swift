import SwiftUI

@main
struct CCUsageBarApp: App {
    @StateObject private var vm = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(vm)
        } label: {
            Label(vm.menuBarLabel, systemImage: vm.menuBarSymbol)
                .opacity(vm.isOffline ? 0.5 : 1.0)
        }
        .menuBarExtraStyle(.window)
    }
}
