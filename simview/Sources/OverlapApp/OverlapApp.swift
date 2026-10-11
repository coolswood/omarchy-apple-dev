// Overlap regression app: a button whose label is another button. Both hit
// rects are identical, so the topmost-order rule of hit testing has a
// visible outcome: the inner button, placed later, must win the touch.

import SwiftUI

@main
struct OverlapApp: App {
  var body: some Scene {
    WindowGroup {
      OverlapPair()
    }
  }
}

struct OverlapPair: View {
  @State private var which = 0
  var body: some View {
    VStack(alignment: .center, spacing: 16) {
      Button(action: { which = 1 }, label: {
        Button("inner") { which = 2 }
      })
      Text("which: \(which)")
    }
  }
}
