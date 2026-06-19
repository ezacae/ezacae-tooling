---
name: handoff
description: Compacte la conversation en cours dans un document de passation pour qu'un autre agent puisse reprendre le travail.
argument-hint: "A quoi servira la prochaine session ?"
---

Redige un document de passation (handoff) resumant la conversation en cours pour qu'un agent frais puisse continuer le travail. Enregistre le fichier dans le repertoire temporaire du systeme d'exploitation de l'utilisateur — pas dans le workspace courant.

Inclus une section "Skills suggeres" dans le document, qui recommande les skills que l'agent devrait invoquer.

Ne duplique pas le contenu deja capture dans d'autres artefacts (PRD, plans, ADR, issues, commits, diffs). Reference-les par chemin ou URL a la place.

Expurge toute information sensible : cles API, mots de passe ou informations personnellement identifiables.

Si l'utilisateur a passe des arguments, traite-les comme une description de ce sur quoi la prochaine session doit se concentrer et adapte le document en consequence.

## Structure du document

Le document de passation doit suivre cette structure :

```markdown
# Passation — [titre bref du travail en cours]

**Date** : YYYY-MM-DD
**Branche** : [branche git courante]
**Repertoire de travail** : [chemin absolu]

## Contexte

[Resume en 2-3 phrases de ce que l'utilisateur essaie d'accomplir et pourquoi.]

## Ce qui a ete fait

- [Liste a puces des actions completees dans cette session]
- [Inclure les fichiers crees/modifies avec leur chemin]
- [Mentionner les commits realises avec leur hash court]

## Etat actuel

[Description de l'etat du code/projet a cet instant. Ce qui marche, ce qui ne marche pas encore.]

## Problemes rencontres

- [Problemes identifies mais non resolus]
- [Blocages ou decisions en attente]

## Prochaines etapes

1. [Prochaine action concrete a realiser]
2. [Action suivante]
3. [...]

## Artefacts de reference

| Type | Chemin / URL |
|------|-------------|
| Plan | [chemin vers le plan si existant] |
| Commits | [hash courts des commits pertinents] |
| Branches | [noms des branches concernees] |
| Issues | [references aux tickets/issues] |
| Docs | [chemins vers la documentation pertinente] |

## Skills suggeres

[Liste des skills que le prochain agent devrait invoquer pour continuer le travail, avec une breve justification pour chacun.]

| Skill | Raison |
|-------|--------|
| `/skill-name` | [Pourquoi ce skill est pertinent pour la suite] |

## Notes pour le prochain agent

[Toute information contextuelle importante qui ne rentre pas dans les sections precedentes : preferences de l'utilisateur, contraintes techniques, pieges a eviter, decisions prises et leur justification.]
```

## Processus

1. **Analyser la conversation** : parcourir l'historique pour identifier le contexte, les actions realisees, les problemes et les prochaines etapes.
2. **Collecter l'etat git** : branche courante, fichiers modifies, commits recents de la session.
3. **Identifier les artefacts** : lister les fichiers, plans, PRD, issues referencees dans la conversation.
4. **Suggerer les skills** : determiner quels skills seront utiles pour la suite du travail.
5. **Rediger le document** en suivant la structure ci-dessus.
6. **Expurger** toute donnee sensible.
7. **Enregistrer** dans le repertoire temporaire du systeme (`$TMPDIR` sur macOS/Linux, `%TEMP%` sur Windows) avec un nom explicite : `handoff-[sujet]-[date].md`.
8. **Informer l'utilisateur** du chemin du fichier genere.
