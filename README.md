# ForeverCompanion

Le compagnon complet hors combat pour **WoW Forever** (le Classic+ officiel de Blizzard).
*The complete out-of-combat companion for WoW Forever. English, French, German, Spanish, Portuguese, Italian and Russian.*

WoW Forever applique les restrictions d'addons de Midnight : aucun addon ne peut lire le combat.
ForeverCompanion se concentre donc sur tout le reste : montée, routes d'XP, donjons et raids avec
taux de drop, rerolls, sacs, carte, campements, interface et sécurité.

## Installation

1. Copier le dossier `ForeverCompanion` dans `World of Warcraft\_forever_\Interface\AddOns\`
   (le nom exact du dossier `_forever_` dépend du client Forever).
2. Lancer le jeu, activer l'addon dans la liste des addons.
3. Taper `/fc` pour ouvrir les options.

## Modules

| Module | Ce qu'il fait |
| --- | --- |
| Montée 1-60 | Fenêtre d'XP : XP/heure, temps avant le niveau, repos, XP des quêtes prêtes à rendre. Acceptation et rendu automatiques des quêtes en option (Maj pour ignorer). |
| Route d'XP | Assistant de quêtes : les prochaines quêtes à prendre, faire et rendre selon race, faction, classe et niveau, la plus proche d'abord, avec la flèche dessus. Donjons conseillés pour ton niveau. Routes écrites étape par étape et enregistreur de route. |
| Guide de leveling | Façon RestedXP : route intégrée de 1 à 60 optimisée pour ta race et ta classe avec les nouvelles quêtes de Forever et les donjons à faire au bon niveau (prendre, faire, rendre, voyager), rappel quand un objet BiS de ton niveau est à récupérer, les 5 meilleurs objets par emplacement tous les 5 niveaux selon ta classe et ta faction, nouveaux donjons de Forever compris, avec où les obtenir, talents niveau par niveau, sorts appris et leur coût, rotation selon ton niveau. `/fc lvl`. |
| Flèche | Flèche vers l'étape ou le point de passage, avec la distance. `/fc way 45.2 61.8 Titre`. |
| Carte | Icônes sur la carte du monde (entrées de donjons et raids, quêtes à prendre et à rendre, objectifs, notes, campements), coordonnées, notes personnelles (`/fc note`). |
| Campements | Durées des buffs de camp, campements retenus automatiquement. |
| Rerolls et Legacy | Tous les personnages : niveau, or, métiers, verrouillages, objets, parcours 1-60 terminés. `/fc alts`, `/fc find`. |
| Sacs | Vente des gris, réparation auto, niveau d'objet, objets « Utiliser » et « Équipé » marqués. |
| Collecteur de drops | Mesure les taux de drop des boss et du trash à chaque cadavre fouillé. Export et import pour les partager. |
| Guide des donjons et raids | Tous les donjons et raids : chaque boss avec niveau, PV, butin et taux de drop, chaque monstre du trash avec son butin et ses taux, les quêtes de chaque donjon (donneur, position, objectifs, récompenses), chemin vers l'entrée, liste de souhaits avec alerte. |
| Économie | Prix de l'hôtel des ventes (scan complet toutes les 15 min et prix vus en parcourant), prix dans les infobulles, historique de l'or sur 30 jours, d'où vient l'or et où il part, recettes de tous les personnages avec coût et bénéfice, liste de courses. `/fc eco`. |
| JcJ | Résultats des champs de bataille, honneur par heure, statistiques par champ de bataille. `/fc pvp`. |
| Hardcore | Alertes de zones et de cibles dangereuses, panneau de survie, vérifications avant un donjon. `/fc hc`. |
| Interface | Barre d'infos (or, sacs, durabilité, latence, FPS), infobulles (niveau d'objet, qui le possède, où il tombe), liens web cliquables. |
| Sécurité | Journal de mort, alertes de durabilité et de sacs, alertes de rares et d'élites dangereux (hors combat). |

## Commandes

```
/fc               options
/fc help          toutes les commandes
/fc menu          menu de toutes les fenêtres (aussi au clic sur le bouton de la minimap)
/fc guide         guide des donjons et raids
/fc lvl [onglet]  guide de leveling (route, gear, talents, spells, rotation)
/fc eco [scan]    économie (prix HV, or, métiers, liste de courses)
/fc pvp           statistiques JcJ
/fc hc            mode Hardcore
/fc route         fenêtre de route (record, stop, note, goto, train, export, lua, import, reset)
/fc way x y       point de passage
/fc note <texte>  note sur la carte
/fc camp [nom]    retenir un campement
/fc alts          mes personnages
/fc find <objet>  chercher un objet sur tous les personnages
/fc drops export  partager ses taux de drop (import pour en ajouter)
/fc deaths        journal de mort
```

## D'où viennent les données

- **Donjons et raids** (`Data/InstanceDB.lua`) : boss, butin et taux de drop des boss d'après
  [AtlasLootClassic](https://github.com/Hoizame/AtlasLootClassic) (GPL) ; points de vie, niveaux, monstres
  du trash et taux de drop du trash d'après [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL v3).
  Les boss ajoutés par Forever et le nouveau butin viennent de Questie et de la base WoW Forever de Wowhead (`Data/InstanceForever.lua`).
- **Quêtes** (`Data/QuestDB.lua`) : 4 455 quêtes de WoW Forever (nouvelles quêtes comprises) avec donneur, rendu et zones d'objectifs, d'après [Questie](https://github.com/Questie/Questie) (GPL v3).
  L'assistant de quêtes s'en sert quand aucune route écrite ne correspond.
- **Quêtes de donjon** (`Data/DungeonQuests.lua`) : 547 quêtes reliées à leur donjon ou raid, avec récompenses, d'après CMaNGOS.
- **Routes de leveling intégrées** (`Data/RoutesAuto.lua`) : calculées par `tools/gen_routes.py` à partir de la base de quêtes
  (niveaux, enchaînements, distances, XP des quêtes et des monstres, donjons). Une route par race et par classe : le simulateur essaie plusieurs réglages et garde le plus rapide.
  Du niveau 1 à environ 22, l'ordre des étapes reprend les guides Forever de **RestedXP**
  ([RXPGuides](https://github.com/RestedXP/RXPGuides), licence [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/)),
  importés par `tools/import_rxp.py` ; la suite (environ 22-60) est calculée par le simulateur.
- **Équipement, talents, sorts, rotations** (`Data/GearGuide.lua`, `Data/ClassGuide.lua`) : générés depuis CMaNGOS
  (statistiques des objets, récompenses de quêtes, butin, sorts des maîtres de classe) avec des pondérations de stats de leveling.
- **Taux mesurés** : le collecteur compte les objets tombés en jeu et les affiche à côté des taux de la base.
  Les données partagées par les joueurs (`/fc drops export`) peuvent être fusionnées à chaque version.
- **Routes d'XP écrites** : enregistrées sur le vrai client Forever avec `/fc route record`, puis
  ajoutées dans `Data/Routes/` (format décrit dans `Data/Routes.lua`).

## Publication sur CurseForge

1. Créer le projet sur CurseForge et noter son identifiant : le mettre dans `## X-Curse-Project-ID` du `.toc`.
2. Créer une clé API CurseForge et l'ajouter au dépôt GitHub comme secret `CF_API_KEY`.
3. Lancer le workflow `Release` (onglet Actions, « Run workflow », numéro de version) ou pousser un tag
   `vX.Y.Z` : le workflow construit le zip avec le packager BigWigs et l'envoie sur CurseForge.

## À vérifier sur le client Forever

- Le numéro `## Interface` du `.toc` (16001 en octobre 2026) : à mettre à jour à chaque patch, `/dump select(4, GetBuildInfo())` en jeu.
- Les positions des entrées d'instance (`Data/Instances.lua`) utilisent les cartes de Classic.
- Le système de campements n'a pas d'API documentée : les buffs de camp sont reconnus par leur nom
  (liste modifiable dans les options).

## Licence

GPL v3 (voir `LICENSE`), à cause des données reprises d'AtlasLootClassic et de CMaNGOS.

Exception : la partie des routes de leveling reprise des guides RestedXP (niveaux 1 à environ 22 dans `Data/RoutesAuto.lua`)
reste sous licence **CC BY-NC-SA 4.0** de ses auteurs (RestedXP) :
crédit obligatoire, usage non commercial uniquement, partage dans les mêmes conditions.
