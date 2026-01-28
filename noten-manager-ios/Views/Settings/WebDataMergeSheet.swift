import SwiftUI

struct WebDataMergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: GradesStore
    
    @State private var resolutions: [String: ResolutionStrategy] = [:]
    @State private var isApplying: Bool = false
    
    private var isDark: Bool { store.darkMode }
    private var isFeminine: Bool { store.theme == "feminine" }
    
    var body: some View {
        NavigationStack {
            List {
                if !store.detectedNewWebSubjects.isEmpty {
                    Section("Neue Fächer") {
                        ForEach(store.detectedNewWebSubjects, id: \.self) { subject in
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                Text(subject)
                                Spacer()
                                Text("Wird hinzugefügt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                if !store.webConflicts.isEmpty {
                    Section("Konflikte & Änderungen") {
                        ForEach(store.webConflicts) { conflict in
                            ConflictRow(conflict: conflict, resolution: Binding(
                                get: { resolutions[conflict.id] ?? conflict.resolution },
                                set: { resolutions[conflict.id] = $0 }
                            ))
                        }
                    }
                } else if store.detectedNewWebSubjects.isEmpty {
                    Text("Keine neuen Daten oder Konflikte gefunden.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daten zusammenführen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        ToolbarIcon(symbol: "xmark", showDot: false)
                    }
                    .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            isApplying = true
                            await store.applyWebImport(resolutions: resolutions)
                            isApplying = false
                            dismiss()
                        }
                    } label: {
                        if isApplying {
                            ToolbarLoadingIcon()
                        } else {
                            ToolbarIcon(symbol: "checkmark", showDot: false)
                        }
                    }
                    .disabled(isApplying)
                    .accessibilityLabel("Übernehmen")
                }
            }
            .overlay {
                if isApplying {
                    ProgressView("Wende Änderungen an...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct ConflictRow: View {
    let conflict: WebDataConflict
    @Binding var resolution: ResolutionStrategy
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(conflict.subjectName)
                    .font(.headline)
                Spacer()
                Text(conflict.gradeId.prefix(8))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Lokal")
                        .font(.caption.weight(.bold))
                    if let localGrade = conflict.localGrade {
                        Text("\(localGrade, specifier: "%.1f") Pt.")
                        if let note = conflict.localNote {
                            Text(note).font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Nicht vorhanden").italic().foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                VStack(alignment: .leading) {
                    Text("Web")
                        .font(.caption.weight(.bold))
                    Text("\(conflict.webGrade, specifier: "%.1f") Pt.")
                    if let note = conflict.webNote {
                        Text(note).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            
            Picker("Aktion", selection: $resolution) {
                Text("Lokal behalten").tag(ResolutionStrategy.keepLocal)
                Text("Web übernehmen").tag(ResolutionStrategy.useWeb)
                if conflict.localGrade != nil {
                    Text("Beide behalten").tag(ResolutionStrategy.keepBoth)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
    }
}
