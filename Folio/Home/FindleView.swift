import SwiftUI

final class FindleViewController: NSHostingController<FindleView> {
    init() {
        super.init(rootView: FindleView())
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Shown from the sidebar's Connect Moodle row while Findle isn't installed or set up.
struct FindleView: View {
    @Bindable private var findle = Findle.shared

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(nsImage: findle.icon)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Space.s) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Theme.Space.s) {
                if findle.status == .notSetUp {
                    Button("Open Findle") { findle.openApp() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Get Findle") { findle.getApp() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Text("Free and open source")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Button("Hide from Sidebar") { findle.setShown(false) }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
                .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
    }

    private var title: String {
        findle.status == .notSetUp ? "Choose your courses in Findle" : "Read your Moodle courses here"
    }

    private var message: String {
        if findle.status == .notSetUp {
            return "Sign in to Moodle in Findle and pick your courses. They’ll appear in the sidebar."
        }
        return "Findle syncs your Moodle courses to your Mac. Once it’s set up, they appear in the sidebar, ready to read and ask about."
    }
}
