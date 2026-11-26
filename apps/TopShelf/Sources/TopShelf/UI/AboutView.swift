import AppKit
import SwiftUI

struct OpenSourceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .frame(width: 24, height: 24)
                    Text("{}")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text("Open Source | Free to Fork & Use")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text("Feel free to fork, modify, use, and contribute!")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Developed by:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("SoftAI Yazılım")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 6) {
                    Text("Developer:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("Assoc. Prof. Dr. Mehmet Akif Cifci")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 6) {
                    Text("GitHub:")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Link("@themanoftalent", destination: URL(string: "https://github.com/themanoftalent")!)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct FollowSupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("❤️")
                    .font(.system(size: 16))
                Text("Follow & Support")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text("If you find this project useful, star the repository, follow me, or buy me a coffee! Your support helps keep future projects free and open-source.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/themanoftalent")!) {
                    HStack(spacing: 6) {
                        Text("</>")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.0, green: 0.48, blue: 1.0))
                        Text("GitHub")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "https://github.com/sponsors/themanoftalent")!) {
                    HStack(spacing: 6) {
                        Text("❤️")
                            .font(.system(size: 12))
                        Text("Sponsor Me")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.red.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Link(destination: URL(string: "https://buymeacoffee.com/themanoftalent")!) {
                    HStack(spacing: 6) {
                        Text("☕")
                            .font(.system(size: 12))
                        Text("Buy Me a Coffee")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct AboutView: View {
    @ObservedObject var store = AppStore.shared

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                    }

                    VStack(spacing: 3) {
                        Text("TopShelf")
                            .font(.system(size: 20, weight: .bold))
                        Text(versionString)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    Text("A modern, lightweight native menu bar folder browser for macOS.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(.top, 4)

                OpenSourceCard()
                FollowSupportCard()

                Divider()
                    .padding(.horizontal, 40)

                VStack(spacing: 4) {
                    let count = store.pinnedFolders.count
                    Text("\(count) \(count == 1 ? "folder" : "folders") pinned")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("All folder data stays strictly local on your Mac. No network telemetry.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}
