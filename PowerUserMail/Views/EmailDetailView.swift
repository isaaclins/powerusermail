import SwiftUI

struct EmailDetailView: View {
    let email: Email

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(email.subject)
                        .font(.title2)
                        .bold()
                    Text("From: \(email.from)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("To: \(email.to.joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(email.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(email.subject)
    }
}
