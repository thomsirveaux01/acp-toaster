import SwiftUI

/// Dialog for adding a new model server or editing an existing one.
struct ServerEditorSheet: View {
    /// The server being edited, or nil when adding a new one.
    let server: Server?

    /// Called with the added or updated server.
    var onSave: (Server) -> Void

    /// Shared app state, owned by ContentView.
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var address: String
    @State private var errorMessage: String?

    init(server: Server? = nil, onSave: @escaping (Server) -> Void = { _ in }) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _address = State(initialValue: server?.hostPort ?? "")
    }

    private var isEditing: Bool { server != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // macOS sheets have no title bar, so the title lives in the content.
            Text(isEditing ? "Edit a server" : "Add a server")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, prompt: Text("127.0.0.1:1235"))
                        .autocorrectionDisabled()
                } footer: {
                    Text("Loopback, LAN, or Tailscale address with a port.")
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
        .frame(width: 420, height: 280)
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
            result = appModel.updateServer(server.id, name: trimmedName, address: trimmedAddress)
        } else {
            result = appModel.addServer(name: trimmedName, address: trimmedAddress)
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
