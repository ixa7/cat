VoilaxaChat iOS
================

Serveur fixe : https://voilaxa.com/chat.php

Parcours de connexion :
1. Mot de passe d'accès du serveur (écran séparé).
2. Pseudo + Clé de chiffrement, comme sur la version web.
3. Liste des rooms puis chat.

L'URL du serveur n'est ni demandée ni enregistrée dans UserDefaults.
Le mot de passe d'accès est effacé après authentification.
La phrase de chiffrement est dérivée localement puis effacée du champ ; la clé dérivée reste uniquement en mémoire tant que l'app est active.
Le passage en arrière-plan verrouille l'app et efface l'état sensible.

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

MISE A JOUR INTERFACE IPHONE
- Le Launch Screen est maintenant genere par iOS afin d'eviter le mode de compatibilite/letterboxing sur les iPhone modernes.
- La conversation occupe tout l'espace disponible.
- Le champ de saisie reste colle au bas de l'ecran via safeAreaInset.
- Le clavier peut etre ferme en faisant glisser la conversation, en touchant la conversation, ou via le bouton "Fermer" au-dessus du clavier.
- AZERTY/QWERTY reste gere par le clavier systeme iOS : appuyer/maintenir le bouton globe pour choisir un clavier installe dans Reglages > General > Clavier > Claviers.
