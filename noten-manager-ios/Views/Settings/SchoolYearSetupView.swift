import SwiftUI

struct SchoolYearSetupView<Header: View>: View {
    let header: () -> Header
    @Binding var schoolYearInput: String
    @Binding var selectedSchoolType: SchoolType
    @Binding var gradeSelection: Int
    let availableSchoolYears: [String]
    let gradeOptions: [Int]
    let accentColor: Color
    let currentSchoolYearId: String
    let error: String?

    init(
        schoolYearInput: Binding<String>,
        selectedSchoolType: Binding<SchoolType>,
        gradeSelection: Binding<Int>,
        availableSchoolYears: [String],
        gradeOptions: [Int],
        accentColor: Color,
        currentSchoolYearId: String,
        error: String?,
        @ViewBuilder header: @escaping () -> Header
    ) {
        self._schoolYearInput = schoolYearInput
        self._selectedSchoolType = selectedSchoolType
        self._gradeSelection = gradeSelection
        self.availableSchoolYears = availableSchoolYears
        self.gradeOptions = gradeOptions
        self.accentColor = accentColor
        self.currentSchoolYearId = currentSchoolYearId
        self.error = error
        self.header = header
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header()

                SettingsCard(
                    title: "Basis-Infos",
                    subtitle: "Schuljahr & Art",
                    systemImage: "info.circle.fill",
                    accent: accentColor
                ) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SCHULJAHR")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(availableSchoolYears, id: \.self) { year in
                                            let isSelected = schoolYearInput == year
                                            let isCurrent = year == currentSchoolYearId

                                            Button {
                                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                    schoolYearInput = year
                                                }
                                            } label: {
                                                VStack(spacing: 6) {
                                                    if isCurrent {
                                                        Text("Aktuell")
                                                            .font(.system(size: 8, weight: .black))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Capsule().fill(isSelected ? .white.opacity(0.3) : accentColor.opacity(0.2)))
                                                            .foregroundStyle(isSelected ? .white : accentColor)
                                                    }

                                                    Text(year)
                                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                                        .foregroundStyle(isSelected ? .white : .primary)

                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "calendar")
                                                        .font(.system(size: 14))
                                                        .foregroundStyle(isSelected ? .white : .secondary)
                                                }
                                                .frame(width: 100, height: 80)
                                                .background(
                                                    ZStack {
                                                        if isSelected {
                                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                                .fill(accentColor)
                                                                .shadow(color: accentColor.opacity(0.3), radius: 6, y: 3)
                                                        } else {
                                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                                .fill(Color.formInputBackground)
                                                        }
                                                    }
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .id(year)
                                            .accessibilityLabel("Schuljahr \(year)")
                                            .accessibilityValue(isSelected ? "Ausgewählt" : "")
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                                .mask(
                                    HStack(spacing: 0) {
                                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                            .frame(width: 20)
                                        Rectangle()
                                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                            .frame(width: 20)
                                    }
                                )
                                .onAppear {
                                    if !schoolYearInput.isEmpty {
                                        proxy.scrollTo(schoolYearInput, anchor: .center)
                                    } else {
                                        proxy.scrollTo(currentSchoolYearId, anchor: .center)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("SCHULART")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            SegmentedPicker(selection: $selectedSchoolType, options: [
                                SegmentedPickerOption(title: "FOS", value: .fos),
                                SegmentedPickerOption(title: "BOS", value: .bos)
                            ])
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)

                SettingsCard(
                    title: "Jahrgangsstufe",
                    subtitle: "Wähle deine aktuelle Klasse",
                    systemImage: "graduationcap.fill",
                    accent: .orange
                ) {
                    HStack(spacing: 12) {
                        ForEach(gradeOptions, id: \.self) { grade in
                            let isSelected = gradeSelection == grade
                            Button {
                                gradeSelection = grade
                            } label: {
                                Text("\(grade).")
                                    .font(.headline)
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(isSelected ? Color.orange : Color.formInputBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Jahrgangsstufe \(grade)")
                            .accessibilityValue(isSelected ? "Ausgewählt" : "")
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)

                if let err = error {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 120)
            }
        }
    }
}
