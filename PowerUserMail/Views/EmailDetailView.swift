import SwiftUI

struct EmailDetailView: View {
    let email: Email

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(email.subject)
                    .font(.title2)
                    .bold()
                    .textSelection(.enabled)

                HStack {
                    Text("From:")
                        .foregroundStyle(.secondary)
                    Text(email.from)
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                }
                .font(.callout)

                HStack {
                    Text("To:")
                        .foregroundStyle(.secondary)
                    Text(email.to.joined(separator: ", "))
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            WebView(htmlContent: email.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(email.subject)
    }
}
