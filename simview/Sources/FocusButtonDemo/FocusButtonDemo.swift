import SwiftUI

@main
struct FocusButtonDemo: App {
  var body: some Scene {
    WindowGroup {
      FocusButtonScreen()
    }
  }
}

struct FocusButtonScreen: View {
  @State private var text = ""
  @State private var count = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      TextField("name", text: $text)
      Button("add") { count += 1 }
      Text("count: \(count)")
    }
  }
}
