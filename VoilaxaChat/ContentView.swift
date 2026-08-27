import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if !model.authenticated {
                    LoginView()
                } else if model.currentRoom != nil {
                    ChatView()
                } else {
                    RoomsView()
                }
            }

            if scenePhase != .active {
                Rectangle()
                    .fill(.black)
                    .ignoresSafeArea()
                    .overlay(Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary))
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Serveur") {
                    TextField("https://exemple.com/chat.php", text: $model.serverURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Mot de passe d’accès", text: $model.accessPassword)
                }
                Section("Chiffrement") {
                    TextField("Pseudo", text: $model.pseudoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Clé de chiffrement", text: $model.encryptionPassphrase)
                }
                Section {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.busy { ProgressView() } else { Text("Entrer") }
                            Spacer()
                        }
                    }
                    .disabled(model.busy)
                }
                if !model.statusMessage.isEmpty {
                    Section { Text(model.statusMessage).foregroundStyle(.secondary) }
                }
                if !model.errorMessage.isEmpty {
                    Section { Text(model.errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Text("La clé de chiffrement n’est pas enregistrée. L’application se verrouille lorsqu’elle passe en arrière-plan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Notes")
        }
    }
}

private struct RoomsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.rooms) { room in
                Button {
                    Task { await model.openRoom(room) }
                } label: {
                    HStack {
                        Text(room.title)
                        Spacer()
                        Text("\(room.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .refreshable { await model.refreshRooms() }
            .navigationTitle(model.pseudoInput.isEmpty ? "Rooms" : model.pseudoInput)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Quitter") { Task { await model.logout() } }
                }
            }
        }
    }
}

private struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.messages) { message in
                                HStack {
                                    if message.mine { Spacer(minLength: 48) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(message.author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(message.text)
                                            .textSelection(.enabled)
                                    }
                                    .padding(10)
                                    .background(message.readable ? Color.secondary.opacity(0.16) : Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    if !message.mine { Spacer(minLength: 48) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: model.messages.count) { _ in
                        if let last = model.messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }

                Divider()
                HStack(alignment: .bottom) {
                    TextField("Message", text: $model.messageDraft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await model.sendMessage() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(model.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(model.currentRoom?.title ?? "Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rooms") { Task { await model.closeRoom() } }
                }
                if model.canClearCurrentRoom {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Vider", role: .destructive) { showClearConfirm = true }
                    }
                }
            }
            .confirmationDialog("Vider cette room pour tout le monde ?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Vider", role: .destructive) { Task { await model.clearCurrentRoom() } }
                Button("Annuler", role: .cancel) {}
            }
            .overlay(alignment: .top) {
                if !model.errorMessage.isEmpty {
                    Text(model.errorMessage)
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                }
            }
        }
    }
}
