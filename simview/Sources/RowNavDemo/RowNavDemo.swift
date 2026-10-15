// M7 demo app: a NavigationLink inside a padded HStack inside a
// NavigationStack. The stack must still rewrite the link into a pushing
// button when rows and padding wrap it.

import SwiftUI

@main
struct RowNavDemo: App {
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        HStack {
          NavigationLink("go") { There() }
          Spacer()
        }
        .padding(10)
        .navigationTitle("home")
      }
    }
  }
}

struct There: View {
  var body: some View {
    Text("there").navigationTitle("there")
  }
}
