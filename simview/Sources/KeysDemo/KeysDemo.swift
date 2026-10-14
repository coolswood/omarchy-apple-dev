import SwiftUI

@main
struct KeysDemo: App {
  var body: some Scene {
    WindowGroup {
      KeysScreen()
    }
  }
}

struct KeysScreen: View {
  @State private var first = ""
  @State private var second = ""
  @State private var echo = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      TextField("first", text: $first, onSubmit: { echo = first })
      TextField("second", text: $second)
      Text("echo: \(echo)")
    }
  }
}
