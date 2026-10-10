<p align="center"><img src="docs/images/icon.png" width="120" alt="Icône de Nunsseop"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>L’encoche de votre MacBook, enfin utile.</b><br>
  Musique, appels, fichiers, un lanceur façon Spotlight, usage de l’IA, notifications d’agents, calendrier et HUD système, à un survol de souris.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=c86bfa&label=release" alt="Dernière version"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 ou ultérieur">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-ff5f8f" alt="Licence MIT"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="Swift natif">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <b>Français</b> · <a href="https://namekun.github.io/Nunsseop/">Site web</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="Encoche déployée avec la lecture en cours et le calendrier">
</p>

*Nunsseop* (눈썹) signifie *sourcil* en coréen : la petite arche au-dessus de votre écran. L’app est gratuite, open source, sans compte, sans abonnement et sans pistage.

## Installation en 30 secondes

```sh
brew install --cask namekun/tap/nunsseop
```

Nécessite [Homebrew](https://brew.sh). Homebrew retire l’attribut de quarantaine, l’app s’ouvre donc tout de suite. Pour la mettre à jour, lancez `brew upgrade --cask nunsseop` ; quand une mise à jour est disponible, Réglages › Général › Mises à jour copie cette commande dans le presse-papiers.

Nécessite macOS 14 Sonoma ou ultérieur. Fonctionne sur Apple silicon et sur Intel, ainsi que sur les écrans sans encoche.

## Votre première minute

1. **Survolez l’encoche.** Elle s’ouvre. Éloignez le pointeur et elle se replie.
2. **Lancez de la musique** dans Music, Spotify, YouTube Music ou n’importe quel navigateur. L’encoche la détecte, et une fois repliée, elle affiche une minuscule pochette et un visualiseur.
3. **Faites un clic droit sur l’encoche → Réglages** pour choisir vos onglets, leur ordre, les pop-ups voulus et la taille.

Il n’y a pas d’icône dans le Dock. Nunsseop vit dans l’encoche.

## Un aperçu

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="Rechercher affichant une app, une commande et un réglage"><br>**Rechercher.** Un lanceur pour les apps, fichiers, commandes, presse-papiers, emoji et calculs, avec le raccourci de votre choix. | <img src="docs/images/tab-ai.png" alt="Usage de l’IA pour Claude Code et Codex"><br>**Usage de l’IA.** Les limites de Claude Code et Codex, sans connexion. |
| <img src="docs/images/shelf.png" alt="Étagère avec la tuile AirDrop"><br>**Étagère.** Posez des fichiers dans l’encoche, ou déposez-les sur AirDrop. | <img src="docs/images/tab-timer.png" alt="Onglet Minuteur"><br>**Minuteur.** Compte à rebours, Pomodoro et chronomètre, de la durée que vous voulez. |
| <img src="docs/images/tab-tools.png" alt="Onglet Outils"><br>**Outils.** Sortie audio, coupure du micro, garder éveillé, enregistrement de l’écran, sélecteur de couleur et capture de texte. | <img src="docs/images/tab-system.png" alt="Onglet Système avec les batteries des appareils"><br>**Système.** Processeur, mémoire, disque, réseau et batteries des appareils. |
| <img src="docs/images/tab-emoji.png" alt="Sélecteur d’emoji"><br>**Emoji.** Tous les emoji, avec recherche, un clic pour copier. | <img src="docs/images/hud-headphones.png" alt="HUD de la batterie des écouteurs"><br>**HUD.** Volume, luminosité, batterie des AirPods et plus encore. |
| <img src="docs/images/collapsed-call.png" alt="Encoche repliée pendant un appel Zoom"><br>**Appels.** L’app d’appel et la durée de la conversation. | <img src="docs/images/collapsed-idle.png" alt="Encoche repliée affichant l’usage restant de Claude Code à gauche et la météo"><br>**D’un coup d’œil.** Choisissez ce que chaque côté de l’encoche fermée affiche. |

## Tout ce qu’elle sait faire

**🎵 Musique**
- **Lecture en cours depuis n’importe quelle app.** Music, Spotify, YouTube Music, et des navigateurs comme Safari, Chrome, Arc, Dia et Aside. Pochette, commandes et barre de progression que l’on peut faire glisser.
- **Paroles synchronisées** via [LRCLIB](https://lrclib.net), sous le titre ou sous l’encoche pendant que vous travaillez.
- **Aperçu discret.** Quand le morceau change, le titre se déploie un court instant.
- **Podcasts et longues vidéos** : sauts de 15 secondes et bouton de vitesse (de 1× à 2×), quand le lecteur le permet.

**🗂️ Pour avancer**
- **Étagère.** Faites glisser des fichiers sur l’encoche et ressortez-les plus tard, avec aperçu des images, PDF et vidéos. Les captures d’écran et les téléchargements terminés peuvent s’y ranger automatiquement. Secouez le pointeur en faisant glisser des fichiers n’importe où et une petite cible de dépôt apparaît juste à côté.
- **Calendrier et rappels.** La date du jour en grand, votre semaine avec un point sur les jours chargés, les événements du jour et des rappels à cocher. Tous les comptes ajoutés à macOS fonctionnent (Google, iCloud, Exchange et d’autres), et vous choisissez les calendriers à afficher.
- **Événements à venir.** Cinq minutes avant le début d’un événement horodaté, l’encoche affiche son titre et le temps restant. Les événements contenant un lien Zoom, Google Meet, Teams, Webex, FaceTime, Whereby ou Chime obtiennent un bouton vert Rejoindre dans Accueil, et un clic sur la notification rejoint la réunion.
- **Une recherche qui peut remplacer Spotlight ou Raycast.** Apps (même hors du dossier Applications), fichiers, commandes et réglages système, historique du presse-papiers, emoji (commencez par `:`) et calculs comme `12*(3+4)`, classés selon ce que vous ouvrez le plus. Les initiales fonctionnent : `vsc` trouve Visual Studio Code. Les flèches choisissent, Retour ouvre.
- **Votre raccourci.** <kbd>⇧⌘Espace</kbd> par défaut, ou enregistrez la combinaison de votre choix dans les Réglages. Nunsseop vous prévient quand macOS ou une autre app l’utilise déjà.
- **Minuteur, historique du presse-papiers, notes et sélecteur d’emoji.** L’historique du presse-papiers reste en mémoire et ignore tout ce qu’un gestionnaire de mots de passe marque comme secret. Les paramètres de suivi comme `utm_` et `fbclid` sont retirés des liens que vous copiez.

**💻 Votre Mac**
- **HUD système.** Volume, luminosité (y compris les écrans externes DDC), rétroéclairage du clavier, charge, verrouillage des majuscules et batterie des AirPods apparaissent dans l’encoche. Elle peut prendre le contrôle des touches de volume et de luminosité pour que le HUD du système reste à l’écart.
- **Statistiques système et batteries.** Processeur, mémoire, disque, réseau, ainsi que votre souris, clavier et trackpad, avec un avertissement quand l’un d’eux faiblit.
- **Indicateur caméra et micro.** Un point sur l’encoche tant qu’une app les utilise.
- **Outils.** Changez de sortie audio, réglez le volume de chaque app (expérimental, macOS 14.2 et ultérieur), coupez le micro, gardez le Mac éveillé, enregistrez l’écran, éjectez des disques, prélevez une couleur n’importe où à l’écran et copiez le texte de n’importe quelle zone de l’écran.
- **Météo, téléchargements, miroir et apps du Dock**, à un survol de souris.

**📞 Même fermée**
- **Appels.** Pendant un appel dans Zoom, FaceTime, Teams, Slack, Discord, WhatsApp ou Google Meet, l’encoche fermée affiche l’app et la durée de la conversation. Elle se base sur l’app qui utilise le micro, donc aucune autorisation supplémentaire n’est nécessaire. Pour Zoom, FaceTime et Meet, vous pouvez couper le micro ou désactiver la caméra depuis l’encoche, sans revenir à l’appel.
- **Votre choix de chaque côté.** Quand rien ne joue, affichez l’usage restant de Claude Code ou Codex, les agents au travail, la batterie, la météo ou la date.
- **Musique et minuteurs.** Une minuscule pochette et un visualiseur pendant la musique, et le temps restant pendant qu’un minuteur tourne.
- **Téléchargements.** L’avancement d’un téléchargement Safari ou Chrome, en pourcentage, d’après la même progression que le Finder affiche sur le fichier. Rien n’interroge le système en boucle.

**🤖 Pour les développeurs**
- **Usage de l’IA.** Les limites de Claude et Codex avec leurs heures de réinitialisation, et la consommation de tokens sur les 5 dernières heures et les 7 derniers jours, tous Claude Code, Codex, gjc, omo et OpenCode confondus. Lu dans des fichiers que ces outils conservent déjà sur votre Mac : il n’y a rien à connecter.
- **Limites de Claude en temps réel (optionnel).** L’onglet Usage de l’IA demande une fois s’il faut récupérer vos limites Claude de 5 heures et hebdomadaires auprès d’Anthropic, environ une fois par heure, avec la connexion que Claude Code garde dans le trousseau. Désactivé tant que vous n’avez pas accepté ; modifiable plus tard dans Réglages › Services.
- **Notifications des agents et des terminaux.** Les hooks de Claude Code, Codex, Gemini CLI et OpenCode, les agents dans Muxy, cmux et herdr, et les sonneries de tmux et WezTerm s’affichent dans l’encoche. Cliquez sur une notification pour ramener au premier plan son terminal, son panneau ou son onglet ([réglage ci-dessous](#notifications-des-agents-et-des-terminaux)).
- **Onglet Notifications.** Les 30 dernières notifications des agents, des terminaux et de votre calendrier, avec un badge pour celles que vous n’avez pas vues ; cliquez sur l’une d’elles pour retourner à sa source. Désactivé par défaut (Réglages › Encoche), et conservé en mémoire uniquement.
- **Agents au travail.** Un élément de l’encoche fermée qui indique combien d’agents de code vous attendent (une main jaune) ou, quand aucun n’attend, combien travaillent (un éclair vert). Pour l’instant, il suit herdr.

**🧩 À votre façon**
- Choisissez vos onglets et leur ordre, ce qu’affichent l’en-tête et l’encoche repliée, et les pop-ups que vous recevez. **Tout ce que vous désactivez cesse de tourner.**
- Sous macOS 26, l’encoche déployée et ses cartes utilisent Liquid Glass, ce qui laisse transparaître doucement l’arrière-plan. Vous réglez l’opacité du verre jusqu’à 100 % pour une encoche noire pleine, ou vous désactivez le verre.
- Sur les écrans sans encoche, l’encoche fermée est une petite pastille avec le logo du sourcil, dans la barre des menus, en verre si vous le souhaitez. Elle s’efface après un temps d’inactivité (de 3 à 60 secondes, ou jamais) et revient quand le pointeur l’atteint ; restez dessus une demi-seconde et elle s’ouvre.
- Choisissez l’écran, la taille et le délai de survol, le lancement à l’ouverture de session, et masquez l’encoche quand le MacBook est fermé.
- Balayez vers le bas pour ouvrir, vers le haut pour fermer, sur le côté dans Accueil pour changer de morceau.
- Disponible en English, 한국어, 日本語, 简体中文, Español, Deutsch et Français, selon la langue de votre Mac.

## FAQ

<details>
<summary><b>macOS indique que Nunsseop ne peut pas être ouverte.</b></summary>

L’app n’est pas encore notarisée : installez-la avec Homebrew (`brew install --cask namekun/tap/nunsseop`). Homebrew retire l’attribut de quarantaine, et l’app s’ouvre tout de suite.
</details>

<details>
<summary><b>Rien ne s’affiche quand je lance de la musique.</b></summary>

Nunsseop affiche ce que macOS déclare comme lecture en cours : le lecteur doit donc apparaître dans le Centre de contrôle. C’est le cas de la plupart des apps et des navigateurs. Voir [le fonctionnement de la lecture en cours](#fonctionnement-de-la-lecture-en-cours) pour la solution de repli.
</details>

<details>
<summary><b>Rechercher peut-il remplacer Spotlight ?</b></summary>

Oui. Ouvrez Réglages → Services, cliquez sur le raccourci et appuyez sur <kbd>⌘Espace</kbd>. Nunsseop vous signalera que Spotlight l’utilise et ouvrira Raccourcis clavier, où vous décochez *Afficher la recherche Spotlight*. Rechercher s’ouvre aussi quand son onglet est masqué.
</details>

<details>
<summary><b>Il y a trop d’onglets.</b></summary>

Faites un clic droit sur l’encoche → Réglages → Encoche, et désactivez ce dont vous n’avez pas besoin. Les fonctions désactivées cessent complètement de tourner.
</details>

<details>
<summary><b>Mon Mac n’a pas d’encoche.</b></summary>

Sur un écran sans encoche, comme un moniteur externe avec le MacBook fermé, l’encoche fermée est une petite pastille avec le logo du sourcil, flottant dans la barre des menus. Le sourcil se soulève quand le pointeur le survole, et l’ouvrir fixe l’encoche au bord supérieur, à sa taille habituelle. Elle s’efface quand elle n’est pas utilisée ; désactivez cela ou changez le délai dans les Réglages. C’est aussi là que vous choisissez l’écran utilisé.
</details>

<details>
<summary><b>Pourquoi l’usage de l’IA affiche-t-il d’anciennes limites Claude ?</b></summary>

Par défaut, les pourcentages de 5 heures et hebdomadaires de Claude proviennent de caches écrits par d’autres outils : le HUD d’[oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) quand vous utilisez Claude Code dans un terminal, ou gjc. La carte indique la date de leur dernière mise à jour. Pour des limites toujours à jour sans eux, activez les limites de Claude en temps réel dans l’onglet Usage de l’IA ou dans Réglages › Services. Les totaux de tokens sont toujours en temps réel.
</details>

<details>
<summary><b>Les touches de volume n’affichent plus le HUD de Nunsseop après une mise à jour.</b></summary>

Les versions antérieures à la 0.8.3 étaient signées d’une manière qui faisait oublier à macOS l’autorisation d’accessibilité à chaque mise à jour. Depuis la 0.8.3, elle est conservée. Si vous venez d’une version plus ancienne, retirez une fois Nunsseop de Réglages Système → Confidentialité et sécurité → Accessibilité, puis autorisez-la à nouveau ; cela prend effet sans redémarrage.
</details>

## Notifications des agents et des terminaux

Nunsseop écoute sur `127.0.0.1:47750` les notifications des outils de votre Mac. Les requêtes doivent présenter le jeton secret stocké dans `~/Library/Application Support/Nunsseop/notify-token`.

Ouvrez Réglages → Alertes et appuyez sur **Connecter** à côté de Claude Code, Codex, Gemini CLI ou OpenCode. Seuls les outils que vous avez utilisés sur ce Mac sont listés. Nunsseop modifie le fichier de réglages de cet outil (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`) ou ajoute un plugin dans `~/.config/opencode/plugins`, et conserve l’ancien fichier avec l’extension `.nunsseop-backup`. Codex n’accepte qu’une seule commande `notify` : si une commande existe déjà, elle continue de s’exécuter après celle de Nunsseop. **Déconnecter** annule la modification. Les sessions lancées ensuite envoient leurs notifications à l’encoche.

Pour configurer Claude Code à la main, appuyez sur **Copier la commande du hook Claude Code** et ajoutez-la à `~/.claude/settings.json` :

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

Les terminaux et les apps d’agents n’ont besoin d’aucun hook :

- **Muxy** et **cmux :** leurs propres notifications sont lues depuis l’app, et ne s’affichent pas quand elle est au premier plan.
- **herdr :** les agents qui terminent ou attendent une réponse, dans toutes les sessions, lus depuis le socket de herdr.
- **tmux :** les sonneries de n’importe quelle fenêtre. Nunsseop ajoute un hook au serveur tmux en cours d’exécution uniquement ; `tmux.conf` n’est pas modifié.
- **WezTerm :** les sonneries, via des lignes que vous copiez depuis Réglages › Alertes et collez dans `~/.wezterm.lua`.

Chacun a un interrupteur dans Réglages › Alertes (WezTerm a plutôt un bouton qui copie ses lignes de configuration), affiché seulement si l’outil est installé. Les outils déjà connectés par leur propre hook ne sont pas affichés deux fois.

N’importe quel script peut aussi en envoyer une :

```sh
curl -X POST http://127.0.0.1:47750/notify \
  -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Nunsseop/notify-token)" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

## Autorisations

Nunsseop ne demande une autorisation que la première fois que vous utilisez la fonction qui en a besoin.

| Fonction | Autorisation | Quand elle est demandée |
| --- | --- | --- |
| Calendrier | Calendriers | Quand vous appuyez sur *Autoriser l’accès* dans l’onglet Accueil |
| Rappels | Rappels | Quand vous appuyez sur *Autoriser les rappels* dans l’onglet Accueil |
| Miroir | Caméra | Quand vous appuyez sur *Autoriser la caméra* dans l’onglet Miroir |
| Enregistrement de l’écran, et copie du texte des fenêtres d’autres apps | Enregistrement de l’écran | La première fois que vous lancez un enregistrement ou une capture de texte |
| Enregistrement avec le son | Micro | La première fois que vous enregistrez avec le son du micro activé |
| Prise de contrôle des touches de volume, de luminosité et de rétroéclairage du clavier | Accessibilité | Quand vous activez l’option dans les Réglages |
| Lecture en cours de secours pour Music, Spotify et les navigateurs | Automatisation | Seulement si l’assistant MediaRemote est indisponible |
| Affichage des appels Google Meet, Zoom et Teams dans un navigateur | Automatisation (ce navigateur) | Quand un navigateur utilise le micro pour la première fois |
| Lancement à l’ouverture de session | Ouverture | Quand vous l’activez dans les Réglages |

## Confidentialité

Nunsseop ne collecte ni n’envoie aucune donnée personnelle. Elle ne se connecte à Internet que pour :

- consulter `api.github.com` une fois par jour à la recherche d’une nouvelle version (peut être désactivé) ;
- chercher des paroles synchronisées sur `lrclib.net` (peut être désactivé) ;
- récupérer la météo auprès de `open-meteo.com` pour la ville que vous saisissez (désactivé tant que vous n’en saisissez pas), en demandant au géocodeur d’Apple les coordonnées de la ville quand Open-Meteo ne la trouve pas ;
- télécharger des pochettes en HTTPS depuis des services musicaux connus, uniquement quand l’assistant MediaRemote est indisponible ;
- demander à `api.anthropic.com` vos limites Claude environ une fois par heure, avec la connexion de Claude Code lue dans le trousseau, uniquement si vous activez les limites de Claude en temps réel.

Tout le reste demeure sur votre Mac. Le serveur de notifications n’accepte que les connexions de ce Mac. L’usage de l’IA est lu dans des fichiers locaux, sauf si vous activez les limites de Claude en temps réel. Les notifications de l’onglet Notifications sont conservées en mémoire uniquement. Les enregistrements sont sauvegardés à côté de vos captures d’écran. L’aperçu de la caméra ne tourne que lorsque l’onglet Miroir est ouvert et n’est jamais enregistré. L’historique du presse-papiers est effacé quand Nunsseop quitte.

## Fonctionnement de la lecture en cours

Depuis macOS 15.4, le framework privé MediaRemote ne répond plus qu’aux processus signés par Apple. Nunsseop embarque une petite bibliothèque d’assistance (`Sources/NowPlayingHelper`) qui s’exécute dans le `/usr/bin/perl` du système, lit l’état de la lecture en cours, envoie les commandes de lecture, pause, changement de piste et positionnement, et renvoie des lignes JSON à l’app.

Cela repose sur une API privée : une future mise à jour de macOS pourrait donc le casser. Dans ce cas, Nunsseop se rabat sur AppleScript pour Music et Spotify, et sur la lecture des onglets multimédias dans les navigateurs. Ce repli exige d’activer *Autoriser JavaScript depuis les Apple Events* dans chaque navigateur. Dia n’a pas d’élément de menu pour cela : Nunsseop propose donc de le relancer avec `--enable-applescript-javascript`.

## Compiler depuis les sources

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

Vous avez besoin des outils en ligne de commande Xcode avec Swift 5.10 ou ultérieur. `scripts/bundle.sh` compile le package Swift et l’enveloppe dans un bundle d’app signé ad hoc.

## Licence

[MIT](LICENSE). Les issues et les pull requests sont les bienvenues.
