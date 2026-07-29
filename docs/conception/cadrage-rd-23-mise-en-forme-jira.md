# Cadrage — Mise en forme des commentaires et descriptions Jira (RD-23)

Statut : Actif — cadrage fonctionnel, entrée de la phase de conception (chuck).

## Le problème

Nos scripts Jira écrivent et relisent du texte destiné à des humains. Aux deux extrémités, la mise en forme est perdue.

**À l'écriture**, tout ce qu'on envoie devient une suite de paragraphes plats. Un titre reste un titre écrit avec des dièses, une liste reste une liste écrite avec des tirets, un bloc de code reste du texte au milieu du reste. Le lecteur voit la syntaxe, pas la mise en forme.

**À la lecture**, c'est pire : le terminal affiche le ticket comme un pavé sans frontières. Les paragraphes se collent les uns aux autres — `RD-17PÉRIMÈTRE RÉEL` — et les éléments de liste disparaissent dans la masse. Illisible dès quelques lignes.

Nuance utile : dans l'interface web de Jira, les paragraphes sont bien conservés. Le défaut d'écriture appauvrit la mise en forme, il ne la détruit pas. Le pavé compact, lui, est propre à notre lecteur terminal. Ce sont donc **deux défauts indépendants**, à traiter séparément.

Le coût est réel et constaté deux jours de suite : RD-10 le 27/07, puis RD-17 le 28/07, où le commentaire de cadrage a dû être reposté en version simplifiée pour rester lisible.

## Ce qu'on a vérifié

Le diagnostic du ticket a été confirmé dans le code, à l'endroit annoncé.

- **Écriture** — `plugins/ezacae-jira/scripts/jira-lib.sh:111`, fonction `jira_text_to_adf`. Elle ne produit qu'un seul type de bloc : le paragraphe nu. Aucun autre élément de mise en forme n'est atteignable.
- **Lecture** — `plugins/ezacae-jira/scripts/jira-get.sh:39` et `:53`. Le texte est aplati en concaténant tous les morceaux sans séparateur, donc sans frontière de bloc. Le filtre est **écrit deux fois** dans le fichier : une correction doit passer aux deux endroits, ou la description et les commentaires divergeront.

## Périmètre

**Côté écriture — 5 commandes concernées, toutes celles qui écrivent du texte :**
`jira-comment.sh`, `jira-create.sh`, `jira-edit.sh`, `jira-transition.sh` (son option `--comment`). Toutes passent par la même fonction : la corriger une fois les couvre toutes.

Constructions à couvrir — le sous-ensemble réellement utilisé dans nos commentaires de pipeline, pas davantage :

1. titres (deux niveaux) ;
2. listes à puces ;
3. listes numérotées ;
4. blocs de code ;
5. gras et italique ;
6. liens.

Les paragraphes et les lignes vides continuent de fonctionner comme aujourd'hui.

**Côté lecture — une seule commande concernée :** `jira-get.sh`. Objectif : un commentaire de 40 lignes reste lisible dans le terminal, avec ses frontières de blocs visibles — une séparation entre paragraphes, un repère par élément de liste, une délimitation pour les blocs de code. `jira-search.sh` n'affiche pas de texte riche : il n'est pas concerné.

**Hors périmètre**, volontairement : tableaux, cartes de ticket intégrées, encarts, mentions d'utilisateur, images. Ces constructions ne servent pas dans nos commentaires de pipeline ; les ajouter élargirait le chantier sans bénéfice constaté.

## Qui est impacté

- **Le lecteur humain d'un ticket** (product, technique, développeur qui reprend un sujet) — bénéficiaire direct, aux deux extrémités : il lit les commentaires dans Jira et relit les tickets depuis le terminal.
- **Les agents du pipeline** (Mike, Sarah, et les rôles qu'ils appellent) — ils écrivent les commentaires de passation et relisent les tickets pour se situer. Un ticket illisible dégrade la qualité de leur reprise de contexte, pas seulement le confort de lecture.
- **Le watcher headless** — il lit les tickets sans intervention humaine. Il doit continuer de fonctionner à l'identique : la correction ne doit rien exiger de nouveau de l'environnement.

## Processus concernés

Le pipeline JIRA de bout en bout, à chaque point où du texte circule :

- **cadrage** — la fiche et le commentaire de passation de Mike ;
- **conception et implémentation** — les comptes rendus et les liens de merge request ;
- **revue** — le rapport de revue, aujourd'hui le texte le plus long et donc le plus abîmé ;
- **lecture de ticket** — à l'entrée de chaque étape, quand un agent ou un humain reprend le fil.

## Contraintes connues

1. **Non-régression stricte.** Un texte sans aucune syntaxe de mise en forme doit produire exactement le même résultat qu'aujourd'hui. C'est vérifiable au caractère près, et ça doit l'être.
2. **Aucun changement de signature.** Les appels existants — dans les scripts, les skills, les commandes, le watcher — ne changent pas. La correction est interne.
3. **Dégradation propre.** Une syntaxe non supportée s'affiche comme du texte ordinaire. Elle ne fait jamais échouer un envoi : perdre un commentaire de passation coûte plus cher que le voir mal mis en forme.
4. **Tests hors-ligne.** Aucun appel réseau, sur le modèle des tests existants du plugin (`plugins/ezacae-jira/tests/test_jira_guard.sh`).
5. **Caractères qui cassent le transport.** Guillemets, antislashs, accolades et emoji doivent être couverts par les tests — nos commentaires en contiennent systématiquement (les préfixes 🤖, les chemins, les extraits de code).
6. **Double correction côté lecture.** Le filtre dupliqué dans `jira-get.sh` impose de traiter les deux occurrences, ou de les factoriser.

## Ce qui reste à trancher en conception

Ces points relèvent de chuck, pas du cadrage :

- où vit le convertisseur et sous quelle forme (la fonction actuelle est un filtre `jq` d'une dizaine de lignes ; la cible est nettement plus large) ;
- comment matérialiser les frontières de blocs à la lecture (choix d'affichage, pas de règle métier) ;
- comment prouver la non-régression au caractère près sur un corpus de textes plats représentatifs.

## Dépendances

- **RD-13 (socle harnais)** — indépendant. Le défaut est dans l'outillage existant, quelle que soit la piste de socle retenue. Rien n'attend cette décision.
- **RD-17** — c'est le ticket sur lequel le pavé illisible a été constaté ; il est aujourd'hui en recette interne. Aucune dépendance technique, seulement l'origine du signalement.

## Contournement en attendant

Passer les textes longs en pièce jointe Markdown (`jira-attach.sh`), avec un commentaire court qui y renvoie. Ça ne corrige rien : ça déplace le texte hors du fil de discussion, là où il est moins lu.
