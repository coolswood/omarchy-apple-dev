// M7 demo app: rows. One padded row with a Spacer between two labels, one
// row of two buttons, a row of two Spacers around a label, and a counter.
// App-style SwiftUI only; built against our SwiftUI module like the others.

import SwiftUI

@main
struct RowDemo: App {
  var body: some Scene {
    WindowGroup {
      Screen()
    }
  }
}

struct Screen: View {
  @State private var taps = 0
  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 4) {
        Text("left")
        Spacer()
        Text("right")
      }
      .padding(10)
      HStack(spacing: 6) {
        Button("minus") { taps -= 1 }
        Button("plus") { taps += 1 }
      }
      HStack {
        Spacer()
        Text("mid")
        Spacer()
      }
      Text("taps: \(taps)")
    }
  }
}
