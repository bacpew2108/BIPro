// Phase F (T093): hộp kết nối cơ sở dữ liệu PostgreSQL, ba bước như Desktop 2.159 (VM-F7b, ảnh d1–d4 ở
// docs/phase-f-evidence/vm-f7/): địa chỉ (máy chủ, cơ sở dữ liệu, "Tuỳ chọn nâng cao": câu SQL) → thông tin đăng nhập (tên, mật khẩu,
// cảnh báo khi bị từ chối; lưu Keychain theo máy chủ) → "Hỗ trợ mã hoá" khi máy chủ không có SSL. Trạng thái ở `NavigatorState.databaseForm`.

import SwiftUI
import Connectors

struct DatabaseConnectView: View {
    @Bindable var state: NavigatorState
    var onClose: () -> Void = {}

    @State private var showsAdvanced = false

    private var form: DatabaseForm { state.databaseForm ?? DatabaseForm() }

    private func binding<T>(_ keyPath: WritableKeyPath<DatabaseForm, T>) -> Binding<T> {
        Binding(get: { (state.databaseForm ?? DatabaseForm())[keyPath: keyPath] },
                set: { state.databaseForm?[keyPath: keyPath] = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch form.step {
                case .address: addressStep
                case .credentials: credentialsStep
                case .encryption: encryptionStep
                }
            }
            .padding(24)
            .disabled(form.isConnecting || state.phase == .listingItems)

            Spacer(minLength: 0)
            footer
                .hairline(.top)
        }
        .frame(width: 560)
        .background(DS.Palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.large))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.large).strokeBorder(DS.Palette.separator, lineWidth: 1))
    }

    // MARK: Bước 1: địa chỉ

    private var addressStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cơ sở dữ liệu PostgreSQL").font(DS.Typeface.headlineMedium)
            labeled("Máy chủ") {
                TextField("máy:cổng (mặc định cổng 5432)", text: binding(\.server)).textFieldStyle(.roundedBorder).frame(width: 300)
            }
            labeled("Cơ sở dữ liệu") {
                TextField("", text: binding(\.database)).textFieldStyle(.roundedBorder).frame(width: 300)
            }
            DisclosureGroup("Tuỳ chọn nâng cao", isExpanded: $showsAdvanced) {
                labeled("Câu lệnh SQL (tuỳ chọn, cần cơ sở dữ liệu)") {
                    TextEditor(text: binding(\.sql))
                        .font(DS.Typeface.mono)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator))
                }
                .padding(.top, 6)
            }
            .font(DS.Typeface.body)
            warningBanner
        }
    }

    // MARK: Bước 2: đăng nhập

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cơ sở dữ liệu PostgreSQL").font(DS.Typeface.headlineMedium)
            Label(form.address.location, systemImage: "cylinder.fill")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
            warningBanner
            labeled("Tên người dùng") {
                TextField("", text: binding(\.user)).textFieldStyle(.roundedBorder).frame(width: 300)
            }
            labeled("Mật khẩu") {
                SecureField("", text: binding(\.password)).textFieldStyle(.roundedBorder).frame(width: 300)
            }
            Toggle("Lưu vào Keychain cho máy chủ \(form.address.server)", isOn: binding(\.savePassword))
                .font(DS.Typeface.body)
                .toggleStyle(.checkbox)
            Text("Mật khẩu không bao giờ được ghi vào tệp .pbix.")
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.tertiaryLabel)
        }
    }

    // MARK: Bước 3: không mã hoá

    private var encryptionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hỗ trợ mã hoá").font(DS.Typeface.headlineMedium)
            Text("Không kết nối được tới nguồn dữ liệu bằng kết nối mã hoá. Muốn truy cập nguồn này bằng kết nối không mã hoá thì bấm OK.")
                .font(DS.Typeface.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        if let warning = form.warning {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.label)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.control).fill(DS.Palette.warning.opacity(0.15)))
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
            content()
        }
    }

    // MARK: Nút

    private var footer: some View {
        HStack(spacing: 8) {
            if form.isConnecting || state.phase == .listingItems {
                ProgressView().controlSize(.small)
                Text("Đang kết nối…").font(DS.Typeface.body).foregroundStyle(DS.Palette.secondaryLabel)
            }
            Spacer()
            if form.step == .credentials {
                Button("Quay lại") { state.databaseForm?.step = .address; state.databaseForm?.warning = nil }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Button("Huỷ") {
                state.cancelDatabase()
                onClose()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
            Button(form.step == .credentials ? "Kết nối" : "OK") {
                Task {
                    switch form.step {
                    case .address: await state.submitDatabaseAddress()
                    case .credentials: await state.submitDatabaseCredentials()
                    case .encryption: await state.acceptUnencrypted()
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(DS.Palette.chrome)
    }

    private var canSubmit: Bool {
        guard !form.isConnecting, state.phase != .listingItems else { return false }
        switch form.step {
        case .address: return form.canSubmitAddress
        case .credentials: return !form.user.isEmpty
        case .encryption: return true
        }
    }
}
