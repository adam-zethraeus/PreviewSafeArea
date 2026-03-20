import SwiftUI
import PreviewSafeArea

struct ContentView: View {
    var body: some View {
        PreviewSafeArea {
            VStack {
                Image(systemName: "globe")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                Text("Hello, world!")
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
