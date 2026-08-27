# VoilaxaChat — iOS

Client de chat chiffré pour iPhone, en SwiftUI natif. Il parle au `chat.php`
du serveur, chiffre et déchiffre sur l'appareil, et ne conserve ni le mot de
passe d'accès ni la clé en mémoire persistante.

L'application s'affiche sous le nom **Notes** sur l'écran d'accueil.

## Construire l'IPA sans Mac

Un push sur `main` déclenche `.github/workflows/ios-build.yml`, qui compile sur
un runner macOS et publie **`VoilaxaChat.ipa`** dans les artefacts du run
(onglet *Actions* → dernier run → *Artifacts*).

L'IPA est **non signé** : la signature se fait à l'installation, avec ton
Apple ID.

- **Windows** : [Sideloadly](https://sideloadly.io/)
- **Linux** : [Sideloader](https://github.com/Dadoum/Sideloader)

Avec un Apple ID gratuit, la signature expire au bout de 7 jours ; il suffit de
réinstaller le même IPA pour la renouveler, sans perdre de données.

Après l'installation : **Réglages → Général → VPN et gestion de l'appareil** →
faire confiance au profil développeur.

## `tools/fix-linkedit.py`

Réserve de la place dans le segment `__LINKEDIT` des binaires avant signature.
Sans lui, la signature ajoutée à l'installation dépasse le `vmsize` du segment
et iOS refuse de lancer l'application :

```
DYLD: segment '__LINKEDIT' filesize exceeds vmsize
```

Le symptôme est une app qui se ferme une seconde après son ouverture, sans
message. La CI applique le correctif automatiquement ; le conserver dans toute
nouvelle chaîne de build.

## Avec un Mac

`build_ipa_on_mac.sh` et `ExportOptions.plist.example` permettent de produire
un IPA signé via Xcode. Voir `README.txt`.

## Icône

`VoilaxaChat/Assets.xcassets/AppIcon.appiconset/` — une seule image 1024×1024,
opaque et sans canal alpha, comme l'exige iOS.
