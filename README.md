## Installation

1. Extraire l'archive
2. S'assurer que la structure des dossiers est maintenue :
   ```
   HGSS Ironmon Scripts/
   ├── configs/
   ├── eventFiles/
   ├── mapToEvent/
   ├── utils/
   ├── savedData/
   └── [fichiers de script]
   ```
3. Charger les scripts individuels via la Console Lua de BizHawk (glissé-déposé ou Script -> Open Scripts dans la Console Lua)
4. S'assurer que les scripts tournent (icone en vert)
5. Ne pas hesiter a sauvegarder la Session Lua (File -> Save Session) et activer l'Autoload Session (File ->  Recent Session > Autoload Session) pour que les scripts se relancent automatiquement au demarrage de Bizhawk 

## Aperçu des Scripts

| Script | Objectif |
|--------|----------|
| **HGSS No Encounter** | Activer/désactiver les rencontres de Pokémon sauvages |
| **HGSS Show IV** | Afficher les IV, EV et puissance des Pokémon (estimations ou exacte) |
| **GUI Configurator** | Positionner et sauvegarder les emplacements des éléments GUI pour HGSS No Encounter, HGSS Show IV, et HGSS Items Alerts |
| **ShowHiddenItemsAndTrainers** | Afficher les objets cachés et les emplacements des dresseurs |
| **HGSS Items Alerts** | Afficher les items importants récoltés |
## Détails des Scripts

### HGSS No Encounter

**Objectif** : Permet d'activer et de désactiver les rencontres de Pokémon sauvages tout en conservant les taux de rencontre originaux lors de la réactivation. Ne doit pas être utilisé avant d'avoir battu la première Arène.

**Commandes** :
- `Select + Haut` : Active les rencontres sauvages
- `Select + Bas` : Désactive les rencontres sauvages

**Fonctionnalités** :
- Préserve les taux de rencontre originaux pour les rencontres
- Affiche le statut actuel à l'écran ("Sauvages : ON/OFF")
- Se remet automatiquement à zéro lorsque la ROM est changée ou rechargée
- Fonctionne pour les rencontres en marchant et en surfant
- Ne désactive les rencontres via Eclate-Roc / Coup d'Boule
---

### HGSS Show IV

**Objectif** : Affiche des statistiques détaillées ou une estimation des Pokémon incluant les Valeurs Individuelles (IV), les Valeurs d'Effort (EV), la puissance estimée et les informations sur Puissance Cachée. L'estimation s'affine au fur et a mesure des niveaux. 

**Commandes** :
- `Select + Droite` : Bascule entre afficher/masquer les informations détaillées des IV
- Cette commande peut être contournée en définissant `always_show_iv = true` dans la configuration

**Informations Affichées** :

**Quand les IV sont affichés** :
- IV individuels pour toutes les statistiques (PV, ATQ, DEF, A.SPE, D.SPE, VIT)
- EV actuels pour toutes les statistiques
- Calcul de la moyenne des IV
- Estimation de la puissance totale (Stats de Base + bonus IV)
- Type et puissance de la Puissance Cachée

**Quand les IV sont masqués** :
- EV seulement
- IV moyens estimés (s'affine a chaque niveau gagné)
- Puissance totale estimée (Stats de Base + bonus IV estimés)

**Code Couleur** :
- **IV** : Rouge (0-5), Orange (6-12), Jaune (13-19), Vert citron (20-26), Vert (27-31)
- **Puissance Totale** : Rouge (<400), Orange (400-449), Jaune (450-499), Vert citron (500-549), Vert (550+)
- **Puissance Cachée** : Code couleur par type

---

### GUI Configurator

**Objectif** : Un script utilitaire pour positionner les éléments GUI d'autres scripts (HGSS No Encounter, HGSS Show IV) sur votre écran.

**Commandes** :
- `Fleches du Clavier` : Déplace l'aperçu GUI autour de l'écran
- `Entrée` : Sauvegarde les paramètres de position actuels

**Fonctionnalités** :
- Montre un aperçu de la façon dont les éléments GUI des autres scripts apparaîtront
- Sauvegarde les paramètres de position dans `configs/gui_settings.cfg`

**Utilisation** :
1. Exécuter ce script en premier pour configurer votre disposition GUI préférée
2. Utiliser les touches fléchées pour positionner l'aperçu où vous voulez que les GUI des autres scripts apparaissent
3. Appuyer sur Entrée pour sauvegarder
4. Les autres scripts utiliseront automatiquement ces positions sauvegardées

---

### ShowHiddenItemsAndTrainers

**Objectif** : Affiche les objets cachés et les emplacements des dresseurs sur votre écran comme marqueurs de superposition.

**Commandes** :
- `Touche R` : Bascule le mode de calibrage pour le positionnement à l'écran
- **En Mode de Calibrage** :
  - `Fleches du Clavier` : Ajuste le positionnement des éléments de superposition, en fonction des paramètres d'affichage de l'utilisateur. L'utilisateur devrait essayer de faire correspondre le point vert au centre de l'écran (en théorie où se trouve le personnage joueur). Conseil : ouvrir le menu du jeu pour eviter que la camera ne bouge.
  - `Entrée` : Sauvegarde les paramètres de calibrage

**Affichage** :
- **Points jaunes ("o")** : Objets cachés qui n'ont pas été collectés
- **Points rouges ("o")** : Dresseurs qui n'ont pas été battus
- Affiche seulement les objets/dresseurs dans un rayon de 8 cases

**Fonctionnalités** :
- Lit automatiquement les données de carte depuis les fichiers events
- Vérifie les flags du jeu pour masquer les objets déjà collectés et les dresseurs battus
- Adapte la superposition en fonction de la taille, de la résolution de l'écran et des paramètre de mise a l'échelle
- Se met en pause pendant les combats
- Supporte toutes les cartes avec les fichiers events correspondants

**Configuration** :
1. Exécuter le script et utiliser le bouton R pour entrer en mode de calibrage si le positionnement semble incorrect
2. Utiliser les fleches du clavier pour aligner le point vert de calibrage avec votre personnage (centre de l'écran)
3. Appuyer sur Entrée pour sauvegarder les paramètres de calibrage

---

### HGSS Items Alerts

**Objectif** : Affiche les items récoltés d'évolutions (avant le premier badge), la corde sortie (si elle n'a pas deja été utilisée pour les ruines alphas) et le nombre de tessons possédés.

---

## Fichiers de Configuration

### `configs/gui_settings.cfg`
- Stocke les offsets X et Y pour le positionnement GUI
- Modifié par GUI Configurator et utilisé par les autres scripts
- Format : `{ x_offset = 0, y_offset = 0 }`

### `configs/show_iv_settings.cfg`
- Contrôle si les IV sont toujours affichés ou nécessitent un basculement par bouton
- Format : `{ always_show_iv = false }`

### `configs/show_hidden_item_settings.cfg`
- Stocke les paramètres de calibrage pour la superposition des objets cachés
- Format : `{ ratioX = 1.0, ratioY = 1.0 }`

## Dépannage

### Problèmes Courants

**Les éléments GUI apparaissent au mauvais endroit** :
- Exécuter GUI Configurator pour définir un positionnement approprié
- Vérifier que les fichiers de configuration ne sont pas corrompus

**Les objets cachés/dresseurs ne s'affichent pas ou s'affichent au mauvais endroit** :
- Utiliser le bouton R pour entrer en mode de calibrage avec ShowHiddenItemsAndTrainers

**Le script plante ou génère des erreurs** :
- Vérifier que l'archive a été correctement extraite et que tous les fichiers sont dans le même dossier

### Adresses Mémoire

Ces scripts utilisent des adresses mémoire spécifiques pour la version française de HGSS. Si vous utilisez différentes versions, les adresses peuvent nécessiter un ajustement dans les fichiers de script.

### Notes de Performance

- Tous les scripts sont optimisés pour fonctionner en continu sans impact significatif sur les performances
- Le script de calcul des IV utilise la mise en cache pour éviter les calculs répétés
- Le script des objets cachés ne se met à jour que lorsque la position du joueur change


