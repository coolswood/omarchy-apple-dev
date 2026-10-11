// M4 demo app: navigation. A list of two rows; each row pushes its own
// detail screen under the navigation bar; the back button pops one level;
// the `deeper` link pushes a third screen. The detail owns @State and shows
// it in its label, so a pushed screen must re-render from live state.
// App-style SwiftUI only; built against our SwiftUI module like the demo.

import SwiftUI

@main
struct NavDemo: App {
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        List {
          NavigationLink("item one") { Detail(label: "one") }
          NavigationLink("item two") { Detail(label: "two") }
        }
        .navigationTitle("demo")
      }
    }
  }
}

struct Detail: View {
  let label: String
  @State private var taps = 0
  var body: some View {
    VStack(spacing: 16) {
      Text("detail \(label)")
      Text("taps: \(taps)")
      Button("tap") { taps += 1 }
      NavigationLink("deeper") { DeepScreen() }
    }
    .navigationTitle(label)
  }
}

struct DeepScreen: View {
  var body: some View {
    Text("deep").navigationTitle("deep")
  }
}
