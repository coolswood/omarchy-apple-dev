import SwiftUI

@main
struct ScrollDemo: App {
  var body: some Scene {
    WindowGroup {
      ScrollScreen()
    }
  }
}

struct ScrollScreen: View {
  @State private var selected = -1
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("selected: \(selected)")
        Quarter(start: 0, select: { selected = $0 })
        Quarter(start: 16, select: { selected = $0 })
        Quarter(start: 32, select: { selected = $0 })
      }
    }
  }
}

struct Quarter: View {
  let start: Int
  let select: (Int) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      FourRows(start: start, select: select)
      FourRows(start: start + 4, select: select)
      FourRows(start: start + 8, select: select)
      FourRows(start: start + 12, select: select)
    }
  }
}

struct FourRows: View {
  let start: Int
  let select: (Int) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Button("item \(start)") { select(start) }
      Button("item \(start + 1)") { select(start + 1) }
      Button("item \(start + 2)") { select(start + 2) }
      Button("item \(start + 3)") { select(start + 3) }
    }
  }
}
