# ForeverCompanion

Le compagnon complet hors combat pour **WoW Forever** (le Classic+ officiel de Blizzard).
*The complete out-of-combat companion for WoW Forever. English and French.*

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
| Route d'XP | Route étape par étape choisie selon race, faction, classe et niveau. Les étapes avancent toutes seules (quête prise, finie, rendue, point atteint). Enregistreur de route pour écrire de nouvelles routes en jouant. |
| Flèche | Flèche vers l'étape ou le point de passage, avec la distance. `/fc way 45.2 61.8 Titre`. |
| Carte | Coordonnées sur la carte et sous la minimap, notes personnelles (`/fc note`). |
| Campements | Durées des buffs de camp, campements retenus automatiquement. |
| Rerolls et Legacy | Tous les personnages : niveau, or, métiers, verrouillages, objets, parcours 1-60 terminés. `/fc alts`, `/fc find`. |
| Sacs | Vente des gris, réparation auto, niveau d'objet, objets « Utiliser » et « Équipé » marqués. |
| Collecteur de drops | Mesure les taux de drop des boss et du trash à chaque cadavre fouillé. Export et import pour les partager. |
| Guide des donjons et raids | Tous les donjons et raids, boss, butin, butin du trash, taux de drop, liste de souhaits avec alerte. |
| Interface | Barre d'infos (or, sacs, durabilité, latence, FPS), infobulles (niveau d'objet, qui le possède, où il tombe), liens web cliquables. |
| Sécurité | Journal de mort, alertes de durabilité et de sacs, alertes de rares et d'élites dangereux (hors combat). |

## Commandes

```
/fc               options
/fc help          toutes les commandes
/fc guide         guide des donjons et raids
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

- **Boss et butin** : le Guide de l'aventurier du client quand il existe, sinon ce que le collecteur a vu.
- **Taux de drop** : mesurés en jeu par le collecteur (`objets tombés / kills`), affichés avec le nombre
  de kills. Les données partagées par les joueurs (`/fc drops export`) sont fusionnées à chaque version.
  `Data/Instances.lua` peut recevoir des taux de référence vérifiés (`ns.DropRates`).
- **Routes d'XP** : écrites depuis le vrai client Forever avec l'enregistreur (`/fc route record`), puis
  ajoutées dans `Data/Routes/` (format décrit dans `Data/Routes.lua`).

## Publication sur CurseForge

1. Créer le projet sur CurseForge et noter son identifiant : le mettre dans `## X-Curse-Project-ID` du `.toc`.
2. Créer une clé API CurseForge et l'ajouter au dépôt GitHub comme secret `CF_API_KEY`.
3. Pousser un tag (`git tag v1.0.0 && git push --tags`) : le workflow `.github/workflows/release.yml`
   construit le zip avec le packager BigWigs et l'envoie sur CurseForge.

## À vérifier sur le client Forever

- Le numéro `## Interface` du `.toc` (16001 en octobre 2026) : à mettre à jour à chaque patch, `/dump select(4, GetBuildInfo())` en jeu.
- Les positions des entrées d'instance (`Data/Instances.lua`) utilisent les cartes de Classic.
- Le système de campements n'a pas d'API documentée : les buffs de camp sont reconnus par leur nom
  (liste modifiable dans les options).
