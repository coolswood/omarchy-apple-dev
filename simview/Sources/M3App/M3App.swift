// M3 test app: two buttons so the drag-across rule has a second target.
// Button#1 shows the state in its label, so one tap changes pixels inside
// the button box. Unchanged app source; built like the demo in build.sh.

import SwiftUI

@main
struct M3App: App {
  var body: some Scene {
    WindowGroup {
      M3View()
    }
  }
}

struct M3View: View {
  @State private var count = 0
  var body: some View {
    VStack(alignment: .center, spacing: 16) {
      Text("taps: \(count)")
      Button("tap \(count)") { count += 1 }
      Button("never") { count += 100 }
    }
  }
}
