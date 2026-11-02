<p align="center">
  <img src="https://ghosting.crowstudios.eu/images/icon.png" width="96" alt="">
</p>

<h1 align="center">Ghosting</h1>

<p align="center">Change la position de ton iPhone en un tap, n'importe où dans le monde.</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=ios&logoColor=white" alt="iOS">
  <img src="https://img.shields.io/badge/Python-3.9%2B-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/SwiftUI-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-CS--SNCL-blue?style=for-the-badge" alt="License">
</p>

Ghosting associe une application iOS à un serveur compagnon sur ton ordinateur pour simuler et modifier la position GPS de ton iPhone en réseau local, sans rester bloqué par un câble.

## Fonctionnalités

### Ghosting (iOS)
- **Recherche de lieux** : Suggestions automatiques pour les villes, adresses et points d'intérêt.
- **Favoris** : Enregistrement et gestion de tes lieux fréquents.
- **Affichage carte** : Ta position réelle reste visible sur la carte pendant la simulation.
- **Live Activity** : Suivi du lieu simulé sur l'écran de verrouillage et dans la Dynamic Island.
- **Connexion automatique** : Détection du Mac sur le réseau local via Bonjour (saisie manuelle IP/Port disponible).

### Ghosting Server (macOS)
- **Changement de position à distance** : Application instantanée des coordonnées envoyées par l'application iOS via `pymobiledevice3`.
- **Détection automatique** : Le Mac s'annonce sur le réseau local.
- **Configuration simplifiée** : Détection de Python et installation automatique des dépendances (`Flask`, `pymobiledevice3`).
- **Arrêt propre** : Rétablissement automatique de la vraie position GPS à la fermeture du serveur.

## Prérequis

- Un **Mac** sous macOS avec Python 3.9 ou supérieur.
- Un **iPhone** sur le même réseau Wi-Fi que le Mac.
- Le **Mode Développeur** activé sur l'iPhone.
- Un premier appairage effectué en **USB** pour accorder la confiance à l'ordinateur.

## Installation

Télécharge le serveur **`Ghosting-Server-1.0.0.dmg`** et l'application **`Ghosting-1.0.0.ipa`** depuis la section [Releases](https://github.com/crowstudios/ghosting/releases).

1. **Sur le Mac** : Ouvre le fichier `.dmg`, glisse **Ghosting Server** dans le dossier `Applications` et lance l'assistant.
2. **Sur l'iPhone** : Installe le fichier `.ipa` via ton outil de sideloading habituel (AltStore, Sideloadly, etc.).

## Licence

Ce projet est sous licence **CrowStudios Source-Available Non-Commercial License (CS-SNCL)**. Consultez le fichier [LICENSE](LICENSE) pour plus de détails.

---
*Propulsé par CrowStudios.*
