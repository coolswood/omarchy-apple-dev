// Nested state regression app, added for the PR review findings: a child
// view owns @State, and the App owns @State too. Per pass the whole tree is
// rebuilt and the state boxes are pooled by slot, so a tap on the child
// button and a tap on the app button both survive the rebuild.

import SwiftUI

@main
struct NestedApp: App {
  @State private var rounds = 0
  var body: some Scene {
    WindowGroup {
      VStack(alignment: .center, spacing: 16) {
        Text("rounds: \(rounds)")
        CounterView()
        Button("next") { rounds += 1 }
      }
    }
  }
}

struct CounterView: View {
  @State private var taps = 0
  var body: some View {
    Button("taps \(taps)") { taps += 1 }
  }
}
