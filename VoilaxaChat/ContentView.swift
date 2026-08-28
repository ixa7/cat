import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if !model.accessAuthenticated {
                    AccessLoginView()
                } else if !model.authenticated {
                    IdentityLoginView()
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

/// Premier écran : équivalent de la porte d'accès PHP de la version web.
private struct AccessLoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Ce mot de passe protège l’accès au chat. La clé de chiffrement des messages sera demandée ensuite et restera sur l’iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("Mot de passe d’accès", text: $model.accessPassword)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await model.loginAccess() }
                        }
                }

                Section {
                    Button {
                        Task { await model.loginAccess() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.busy { ProgressView() } else { Text("Ouvrir") }
                            Spacer()
                        }
                    }
                    .disabled(model.busy || model.accessPassword.isEmpty)
                }

                if !model.errorMessage.isEmpty {
                    Section { Text(model.errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Accès au chat")
        }
    }
}

/// Deuxième écran : même logique que la page web "Pseudo + Clé".
private struct IdentityLoginView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pseudo", text: $model.pseudoInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)

                    SecureField("Clé", text: $model.encryptionPassphrase)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit {
                            Task { await model.enterChat() }
                        }
                }

                Section {
                    HStack(spacing: 12) {
                        Button("Entrer") {
                            Task { await model.enterChat() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || model.pseudoInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.encryptionPassphrase.isEmpty)

                        Button("Test") {
                            Task { await model.testConnection() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.busy)
                    }
                }

                Section {
                    Text("Cette clé sert aux 11 rooms. Avec une mauvaise clé, les messages v6 produiront du texte brouillé, comme sur la version web.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !model.statusMessage.isEmpty {
                    Section { Text(model.statusMessage).foregroundStyle(.secondary) }
                }
                if !model.errorMessage.isEmpty {
                    Section { Text(model.errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Quitter") { Task { await model.cancelAccessSession() } }
                }
            }
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
    @FocusState private var messageFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
                                    .background(
                                        message.readable
                                            ? Color.secondary.opacity(0.16)
                                            : Color.secondary.opacity(0.08)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                    if !message.mine { Spacer(minLength: 48) }
                                }
                                .id(message.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Un glissement vers le bas peut rabattre le clavier.
                    .scrollDismissesKeyboard(.interactively)
                    // Un tap dans la conversation ferme aussi le clavier.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        messageFieldFocused = false
                    }
                    .onChange(of: model.messages.count) { _ in
                        if let last = model.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // La zone de saisie reste collée au bas de l'écran et suit le clavier.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
            .navigationTitle(model.currentRoom?.title ?? "Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Rooms") {
                        messageFieldFocused = false
                        Task { await model.closeRoom() }
                    }
                }

                if model.canClearCurrentRoom {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Vider", role: .destructive) {
                            messageFieldFocused = false
                            showClearConfirm = true
                        }
                    }
                }

                // Barre située juste au-dessus du clavier iOS.
                ToolbarItemGroup(placement: .keyboard) {
                    Text("🌐 AZERTY / QWERTY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Fermer") {
                        messageFieldFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .confirmationDialog(
                "Vider cette room pour tout le monde ?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Vider", role: .destructive) {
                    Task { await model.clearCurrentRoom() }
                }
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

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $model.messageDraft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($messageFieldFocused)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.send)

                Button {
                    Task { await model.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(
                    model.messageDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
                .accessibilityLabel("Envoyer")
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}
