# Feuille de route — Harnais ezacae, cinq sprints

Statut : Brouillon
Rédigée le mercredi 9 septembre 2026 après le point avec Alexandre. Sprints de deux semaines, du lundi au vendredi suivant, sauf le premier qui compte huit jours ouvrés. Chaque sprint se termine par la même chose : une démonstration de quinze minutes, le vendredi, toute l'équipe, où une personne nommée autre que Patrice utilise ce qui a été livré sur un vrai ticket.

## La règle du jeu

- **Un sprint, une chose démontrée.** Ce qui n'est pas dans la colonne « livré » d'un sprint n'existe pas pendant ce sprint. Toute nouvelle idée devient un ticket dans Tooling, jamais un sujet du sprint en cours.
- **Une définition de terminé d'une ligne**, écrite avant le sprint, vérifiable le vendredi.
- **Le banc est le juge** quand la chose se mesure. Le profil vierge du run 2 est réutilisé.
- **La veille outils est gelée** entre deux démonstrations. Le comparatif des méthodes a son sprint, le quatrième.
- **Une seule référence** : le dépôt Tooling. Rien n'y entre sans être passé par un ticket et une relecture.

## Les cinq sprints

| # | Dates | Livré et démontré | Définition de terminé | Utilisateur nommé |
|---|---|---|---|---|
| 1 | 9 → 18 septembre | `/scope` : un besoin devient une épique Jira, une page de cadrage et une page de spécification fonctionnelle après des questions posées à la personne, plus une taille. Porte unique : le fonctionnel validé par un clic du responsable produit dans Jira, refusé à l'assistant par nos scripts. `/to-tickets` (Matt Pocock, branché sur nos scripts Jira) découpe l'épique validée en stories reliées, avec leurs blocages. Originaux `grill-me`, `handoff`, `to-tickets` installés en référence. Ménage des pièces mortes, nouveaux numéros de version, procédure d'installation. | Lyes lance `/scope` sur le besoin du banc depuis son poste, Alexandre valide par un clic dans Jira, Lyes lance `/to-tickets` et les stories reliées apparaissent dans Jira, sans intervention imprévue. | Lyes, Alexandre pour le clic |
| 2 | 21 septembre → 2 octobre | `/develop` pour les stories S et M : lit la taille et le statut, fait la conception du ticket (comment on l'implémente : données, composants, choix, une page), écrit le plan, code tests d'abord, prépare la merge request. Trois portes par statut Jira, chacune un clic humain : conception validée, plan validé, livraison validée. Écriture du code dans un agent séparé et isolé, sur le modèle déclaré, imposé par garde-fou. Dépendance manquante = arrêt. Run 3 du banc contre run 2. | Les stories du banc, créées au sprint 1, sont développées par `/develop` jusqu'à la merge request : c'est le run 3. Il donne 115 / 115 au juge, moins de temps et de coût que le run 2, zéro dérogation. | Développeur à désigner par Alexandre avant le 18 |
| 3 | 5 → 16 octobre | Diffusion et adoption : Cowork et claude.ai, contrôle de version dans les scripts Jira, carte des compétences par situation (README et Google Doc), installation collective, compte Jira dédié si financé. `/document` minimal : les pages de `/scope` rangées dans la documentation du projet, et la documentation d'architecture si c'est ce qu'Alexandre entend par « conception » dans l'amont (question 1 de la spec). | Alexandre lance `/scope` dans Cowork sur un besoin non technique ; chacun des cinq destinataires a invoqué une commande, une ligne par personne dans Google Chat. | Alexandre, puis les cinq |
| 4 | 19 → 30 octobre | Coût et qualité : découpage du travail de l'agent de code en phases courtes à contexte frais (56 % du coût du run 2), comparatif superpowers contre Pocock en un run du banc, juge niveau 2 (cas limites de saisie), aide au découpage d'une épique L en plusieurs épiques par `/scope`. | Un run 4 du banc, même score, coût inférieur au run 3 ; décision écrite sur la boîte à méthodes, en une semaine, au consentement. | Les développeurs, sur leurs tickets |
| 5 | 2 → 13 novembre | Un projet client de bout en bout avec la chaîne complète, de `/scope` à la merge request. Rétrospective d'équipe. Distillation dans la Méthode Harnais et proposition courte sur la documentation société et la mémoire d'entreprise, enfin fondées sur du vécu. | Un ticket client livré par la chaîne, relu par le client ; la rétrospective produit la liste des trois sprints suivants. | Toute l'équipe |

## Ce que chaque sprint suppose du précédent

- Le sprint 2 suppose les stories du banc créées par `/to-tickets` au sprint 1, le projet Jira de test et le dépôt GitLab de test.
- Le sprint 3 suppose `/develop` stable pour que la carte des compétences décrive quelque chose de vrai.
- Le sprint 4 suppose le run 3 comme référence de coût.
- Le sprint 5 suppose un projet client volontaire, à choisir au sprint 3.

## Ce qui n'est dans aucun sprint

La recherche d'outils hors besoin d'un pilote. La relecture des notes du vault et des audits de mars à juin : la lecture est faite. Toute pièce de Matt Pocock autre que `grill-me`, `handoff`, `to-tickets`, et ce que le sprint 4 aura décidé.
