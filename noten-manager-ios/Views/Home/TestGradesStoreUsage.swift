import SwiftUI

struct TestGradesStoreUsage: View {
    @EnvironmentObject var store: GradesStore
    
    var body: some View {
        Text("Test")
            .onAppear {
                if let subject = store.subjects.first {
                    let val = store.bestAvailableHalfYearValue(subject: subject, halfYear: 1)
                    print(val ?? "Nil")
                }
            }
    }
}
