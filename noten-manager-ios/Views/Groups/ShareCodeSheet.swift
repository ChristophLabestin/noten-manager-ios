import SwiftUI
import CoreImage.CIFilterBuiltins

enum ShareCodeType {
    case group
    case socialGroup
    case schoolClass
    
    var title: String {
        switch self {
        case .group, .socialGroup: return "Gruppe teilen"
        case .schoolClass: return "Klasse teilen"
        }
    }
    
    var subtitle: String {
        switch self {
        case .group, .socialGroup: return "Teile diesen Code, damit andere der Gruppe beitreten können."
        case .schoolClass: return "Teile diesen Code, damit andere der Klasse beitreten können."
        }
    }
    
    var deepLinkPath: String {
        switch self {
        case .group, .socialGroup: return "group"
        case .schoolClass: return "class"
        }
    }
}

struct ShareCodeSheet: View {
    @EnvironmentObject var store: GradesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let code: String
    let name: String
    let type: ShareCodeType
    
    @State private var copied = false
    
    private var deepLink: URL? {
        URL(string: "notenmanager://join/\(type.deepLinkPath)/\(code)")
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.indigo.opacity(0.15))
                                .frame(width: 72, height: 72)
                            Image(systemName: type == .group ? "person.3.fill" : "rectangle.stack.person.crop.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.indigo)
                        }
                        Text(name)
                            .font(.title2.weight(.bold))
                        Text(type.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 16)
                    
                    // QR Code Card
                    SettingsSectionBox {
                        VStack(spacing: 16) {
                            if let qrImage = generateQRCode(from: deepLink?.absoluteString ?? code) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                                    .padding(12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            // Code Display
                            VStack(spacing: 4) {
                                Text("Code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(code)
                                    .font(.system(.title3, design: .monospaced).weight(.bold))
                                    .foregroundStyle(.primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button {
                            copyCode()
                        } label: {
                            Label(copied ? "Kopiert!" : "Code kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SoftTintButtonStyle(accent: copied ? .green : .indigo))
                        
                        if let link = deepLink {
                            ShareLink(item: link) {
                                Label("Link teilen", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SoftTintButtonStyle(accent: .blue))
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .background(ThemedBackground(isDark: store.darkMode, isFeminine: store.theme == "feminine", intensity: store.themeBackgroundIntensity))
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .imageScale(.medium)
                            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    }
                }
            }
        }
    }
    
    private func copyCode() {
        UIPasteboard.general.string = code
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { copied = false }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale QR code
        let scale = 10.0
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
