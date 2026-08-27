VOILAXA CHAT iOS

1. Remplace chat.php sur ton serveur par le chat.php fourni séparément.
2. Vérifie que le site fonctionne en HTTPS.
3. Ouvre VoilaxaChat.xcodeproj dans Xcode sur un Mac.
4. Target VoilaxaChat > Signing & Capabilities : choisis ton Apple Team.
5. Change le Bundle Identifier si Xcode le demande.
6. Branche l'iPhone 12 et lance l'app, ou Archive > Distribute App pour produire un IPA signé.

L'app :
- communique directement avec le même chat.php ;
- utilise une URLSession éphémère (pas de cache HTTP persistant) ;
- ne sauvegarde ni le mot de passe d'accès ni la clé de chiffrement ;
- chiffre/déchiffre côté iPhone ;
- reste compatible avec les messages v6 AES-CTR actuels et lit les anciens v5 AES-GCM ;
- efface les secrets de sa mémoire logique lorsqu'elle passe en arrière-plan.

IMPORTANT : un IPA installable doit être signé par Apple avec ton certificat/profil de provisioning. Le projet ne contient volontairement aucun certificat ni secret Apple.
