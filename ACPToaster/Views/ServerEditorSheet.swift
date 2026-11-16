import SwiftUI

struct ServerEditorSheet: View {
    let server: Server?

    var onSave: (Server) -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var address: String
    @State private var icon: String
    @State private var apiKey: String
    @State private var errorMessage: String?

    init(server: Server? = nil, onSave: @escaping (Server) -> Void = { _ in }) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _address = State(initialValue: server?.hostPort ?? "")
        _icon = State(initialValue: server?.icon ?? ServerIcon.macDesktop.symbol)
        _apiKey = State(initialValue: server?.apiKey ?? "")
    }

    private var isEditing: Bool { server != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // macOS sheets have no title bar, so the title lives in the content.
            Text(isEditing ? "Edit server" : "Add server")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
                    Picker("Icon", selection: $icon) {
                        ForEach(ServerIcon.allCases) { option in
                            Label(option.label, systemImage: option.symbol)
                                .tag(option.symbol)
                        }
                    }
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, prompt: Text("127.0.0.1:1235"))
                        .autocorrectionDisabled()
                    SecureField("API key", text: $apiKey, prompt: Text("Optional"))
                        .autocorrectionDisabled()
                } footer: {
                    Text("Loopback, LAN, or Tailscale address with a port. Leave the API key empty for servers that don't require auth.")
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || trimmedAddress.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 360)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let result: Result<Server, AppModelError>
        if let server {
            result = appModel.updateServer(server.id, name: trimmedName, address: trimmedAddress, icon: icon, apiKey: apiKey)
        } else {
            result = appModel.addServer(name: trimmedName, address: trimmedAddress, icon: icon, apiKey: apiKey)
        }
        switch result {
        case .success(let server):
            onSave(server)
            dismiss()
        case .failure(let error):
            errorMessage = error.message
        }
    }
}

#Preview {
    ServerEditorSheet()
        .environment(AppModel())
}
