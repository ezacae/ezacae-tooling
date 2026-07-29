# Mise en forme des textes Jira — convertisseur ligne-orienté et rendu terminal

> **Pour l'exécution :** `/developer docs/conception/rd-23-mise-en-forme-jira.md` (implémentation autonome).
> **REQUIRED SUB-SKILL** pour un worker agentique : `superpowers:subagent-driven-development` ou `superpowers:executing-plans`. Les étapes sont en cases à cocher.

Ticket : **RD-23** — type : **modification** (deux défauts indépendants dans l'outillage existant).
Cadrage fonctionnel : `docs/conception/cadrage-rd-23-mise-en-forme-jira.md`.

**Objectif :** produire de la structure Jira (titres, listes, blocs de code) à l'écriture, et restituer les frontières de blocs sans perdre de contenu à la lecture — sans changer le comportement actuel sur un texte sans mise en forme.

**Architecture :** deux programmes jq stockés dans `jira-lib.sh`, l'un pour l'écriture (état ligne à ligne), l'autre pour la lecture (rendu récursif). Aucun nouveau fichier de script, aucune nouvelle dépendance, aucune signature modifiée. Un filet de sécurité en bash replie sur la conversion plate actuelle si la structure produite viole les invariants Jira, afin qu'un envoi ne puisse jamais échouer.

**Stack :** bash (POSIX + bashismes déjà présents), jq, curl. Rien d'autre.

## Contraintes globales

Elles s'appliquent implicitement à **toutes** les tâches.

- **Dépendances inchangées** : bash + jq + curl. Interdiction d'introduire python, node, ou tout binaire supplémentaire.
- **`jira-lib.sh` reste muet au chargement.** Le hook `jira-guard.sh` lit son propre stdout comme du JSON (`jira-lib.sh:8-9`). Les programmes jq sont stockés dans des **variables**, jamais exécutés au chargement. Aucun `echo`, aucun `command -v`, aucun avertissement au niveau du fichier.
- **Signatures inchangées** : `jira_text_to_adf` lit stdin et écrit le document sur stdout. Les cinq appelants (`jira-comment.sh:27`, `jira-transition.sh:61`, `jira-create.sh:24,27`, `jira-edit.sh:32,35`) ne sont pas modifiés.
- **Un envoi ne doit jamais échouer** à cause de la mise en forme. En cas de doute, on envoie du texte plat.
- **Aucun pré-traitement en bash** du texte à convertir : ni `sed`, ni `tr`, ni substitution de paramètre. Tout passe par jq, qui seul gère l'échappement JSON (guillemets, antislashs, accolades, emoji).
- **Tests hors-ligne** : aucun appel réseau dans la suite de tests. Modèle : `plugins/ezacae-jira/tests/test_jira_guard.sh`.
- **Français** dans les commentaires de code et les messages, comme le reste du plugin.

---

## Grammaire d'écriture (le contrat)

Le convertisseur est **orienté ligne**. Il examine chaque ligne indépendamment et ne promeut que celles dont le **début** correspond à un motif. Toute ligne non reconnue devient un paragraphe, exactement comme aujourd'hui.

Ordre de priorité, du plus fort au plus faible :

| # | Motif (début de ligne) | Produit |
|---|---|---|
| 1 | ` ``` ` ouvre/ferme un bloc | `codeBlock` |
| 2 | `## ` ou `### ` suivi d'un caractère non blanc | `heading` niveau 2 ou 3 |
| 3 | `- ` suivi d'un caractère non blanc | élément de `bulletList` |
| 4 | `1. ` (un ou plusieurs chiffres, point, espace) suivi d'un caractère non blanc | élément de `orderedList` |
| — | tout le reste | `paragraph` (comportement actuel) |

### Règles précises

**Blocs de code.** Une ligne dont le contenu commence par ` ``` ` ouvre un bloc ; ce qui suit sur la même ligne est le langage (`​```bash` → `attrs.language = "bash"`). Une ligne réduite à ` ``` ` le ferme. **À l'intérieur, aucune promotion** : les lignes sont accumulées telles quelles. C'est ce qui protège les extraits shell (`# commentaire` ne devient pas un titre, `-f fichier` ne devient pas une puce). Un bloc **jamais fermé** dégrade : la ligne d'ouverture et les lignes accumulées ressortent en paragraphes, dans l'ordre d'origine.

**Titres.** `##` → niveau 2, `###` → niveau 3. Un seul `#` n'est pas reconnu (une ligne `#!/usr/bin/env bash` reste un paragraphe). Quatre `#` ou plus ne sont pas reconnus.

**Listes.** Les éléments consécutifs forment une seule liste ; la première ligne non-élément la ferme. Une ligne vide la ferme aussi et produit le paragraphe vide habituel. **Pas d'imbrication** : `  - item` indenté reste un paragraphe. Une liste numérotée qui ne commence pas à 1 porte `attrs.order`.

**Un marqueur seul ne promeut rien.** `## `, `- `, `1. ` sans contenu derrière restent des paragraphes. Cette règle unique évite de produire des nœuds texte vides, que Jira refuse.

**`•` n'est pas un marqueur.** Le format de commentaire de passation actuel (skill `jira-pipeline` §8) utilise `• `. Le promouvoir changerait le rendu de textes qui ne contiennent aucune syntaxe de mise en forme, ce que la non-régression interdit. Faire passer les gabarits de `• ` à `- ` relève du ticket compagnon sur la rédaction, pas de celui-ci.

**Gras, italique, liens : hors périmètre.** Aucune recherche de paires de signes au milieu des phrases. Justification dans le cadrage.

### Formes ADF exactes

Première cause de refus d'envoi : une imbrication approximative. Ces formes sont le contrat.

```json
{"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Titre"}]}

{"type":"bulletList","content":[
  {"type":"listItem","content":[
    {"type":"paragraph","content":[{"type":"text","text":"élément"}]}]}]}

{"type":"orderedList","attrs":{"order":3},"content":[
  {"type":"listItem","content":[
    {"type":"paragraph","content":[{"type":"text","text":"élément"}]}]}]}

{"type":"codeBlock","attrs":{"language":"bash"},
 "content":[{"type":"text","text":"ligne 1\nligne 2"}]}
```

`attrs` est **omis** quand il n'y a rien à mettre (pas de langage, liste démarrant à 1). Un `codeBlock` vide s'écrit `{"type":"codeBlock"}` sans `content` : un nœud texte vide est invalide.

L'enveloppe ne change pas, dans cet ordre de clés : `{"type":"doc","version":1,"content":[…]}`.

### Invariants de validité (vérifiables hors-ligne)

Ce n'est pas le schéma officiel de Jira, c'est le sous-ensemble qui couvre nos erreurs possibles. Le filet de sécurité s'appuie dessus.

1. Aucun nœud `text` dont `text` est la chaîne vide.
2. Tout enfant de `listItem` est un `paragraph`, un `bulletList` ou un `orderedList`.
3. Tout enfant de `bulletList` / `orderedList` est un `listItem`.
4. `heading.attrs.level` est un entier de 1 à 6.
5. Un `codeBlock` contient au plus un nœud, de type `text`, sans `marks`.

---

## Rendu de lecture (le contrat)

Deux exigences distinctes, la seconde plus importante que la première.

**Frontières de blocs.** Les blocs sont séparés par une ligne vide. Un titre est préfixé de ses `#`. Un élément de liste est préfixé de `- ` ou de `N. `. Un bloc de code est encadré de ` ``` `. Une ligne horizontale devient `---`. Une citation est préfixée de `> `. Une ligne de tableau devient `| a | b |`.

**Non-perte.** Tout type de bloc inconnu retombe sur une extraction récursive de son texte. **Rien ne disparaît jamais.** Au niveau du texte en ligne :

| Nœud | Rendu |
|---|---|
| `text` | `.text` |
| `hardBreak` | retour à la ligne |
| `mention`, `emoji` | `attrs.text` |
| `inlineCard` | `attrs.url` |
| autre | `attrs.text`, sinon `attrs.url`, sinon descente récursive dans `content` |

Ce dernier point corrige un défaut **actuel** : les cartes de ticket liées disparaissent aujourd'hui, d'où le `The linked issue -  has been resolved` observé sur RD-23.

---

## Pas d'interface

Aucun écran, aucun composant : l'outil est en ligne de commande. Section UX sans objet, pas de maquette.

---

## Fichiers touchés

| Fichier | Rôle |
|---|---|
| `plugins/ezacae-jira/scripts/jira-lib.sh` | Modifier : remplacer `jira_text_to_adf` (l. 107-117) ; ajouter les variables de programme jq `JIRA_JQ_TEXT_TO_ADF`, `JIRA_JQ_TEXT_TO_ADF_FLAT`, `JIRA_JQ_ADF_VALID`, `JIRA_JQ_ADF_RENDER` |
| `plugins/ezacae-jira/scripts/jira-get.sh` | Modifier : remplacer les deux `def adf_text` (l. 39 et 53) par le rendu partagé |
| `plugins/ezacae-jira/tests/test_adf_write.sh` | Créer : non-régression, sûreté littérale, constructions, validité |
| `plugins/ezacae-jira/tests/test_adf_read.sh` | Créer : frontières de blocs, non-perte |
| `plugins/ezacae-jira/tests/fixtures/plain/*.txt` | Créer : corpus de textes sans mise en forme |
| `plugins/ezacae-jira/tests/fixtures/plain/*.adf.json` | Créer : références figées **avant** modification |
| `plugins/ezacae-jira/tests/fixtures/reference.md` | Créer : texte couvrant les quatre constructions |
| `.gitlab-ci.yml` | Modifier : job qui lance les tests shell du dépôt |

Découpage : la responsabilité reste dans `jira-lib.sh` parce que la garde de statut y est déjà mutualisée — c'est le motif établi du plugin. Pas de nouveau fichier de bibliothèque.

---

## Risques et parades

**Un envoi refusé casse une passation.** Dans `jira-transition.sh:57-65`, le commentaire part *après* le changement de statut. Un refus laisse le ticket transitionné sans commentaire, et la garde interdit de rejouer la transition. Parade : le filet de sécurité de la tâche 6 — la structure est vérifiée localement avant l'envoi et, si elle est invalide, on envoie le texte plat avec un avertissement sur stderr. L'envoi aboutit toujours.

**La référence de non-régression devient tautologique.** Si la fonction est modifiée avant que les références soient figées, elles enregistrent le nouveau comportement. Parade : la tâche 1 fige les références et **ne touche à rien d'autre**. C'est un point de non-retour du plan.

**Les tests de la tâche 1 passent dès l'écriture.** Ce sont des tests de caractérisation : ils décrivent le comportement actuel pour le protéger. Il n'y a **pas** d'étape rouge pour eux, et c'est normal. Ne pas chercher à les faire échouer.

**Le hook casse en silence.** Un message ajouté au chargement de `jira-lib.sh` rendrait invalide le JSON du hook et bloquerait toutes les opérations Jira du dépôt. Parade : la tâche 8 vérifie que le chargement de la bibliothèque n'écrit rien, et `test_jira_guard.sh` doit rester vert de bout en bout.

**Rien ne tourne automatiquement.** Aucun job n'exécute les tests shell aujourd'hui. Parade : tâche 9. Sans elle, la garantie de ce ticket expire au premier oubli.

---

## Plan d'implémentation

Ordre choisi : figer, puis corriger la **lecture**, puis l'**écriture**. La lecture d'abord parce qu'elle est indépendante et qu'elle rend les phases d'écriture vérifiables à l'œil dans le terminal.

Toutes les commandes se lancent depuis la racine du dépôt.

---

### Tâche 1 : figer les références de non-régression

**Fichiers :**
- Créer : `plugins/ezacae-jira/tests/fixtures/plain/simple.txt`, `accents.txt`, `json-hostile.txt`, `vides.txt`
- Créer : `plugins/ezacae-jira/tests/fixtures/plain/*.adf.json` (générés)
- Créer : `plugins/ezacae-jira/tests/gen-fixtures.sh`

**Interfaces :**
- Consomme : `jira_text_to_adf` **dans sa version actuelle, non modifiée**
- Produit : les fichiers `*.adf.json` qui servent de référence à la tâche 2

- [ ] **Étape 1 : écrire les textes du corpus**

`fixtures/plain/simple.txt` :
```
Première ligne de texte.
Deuxième ligne, juste après.

Après une ligne vide.
```

`fixtures/plain/accents.txt` :
```
Périmètre arbitré le 29/07 — décision prise à l'unanimité.
Coût constaté : élevé. Où ? Sur RD-10 puis RD-17.
```

`fixtures/plain/json-hostile.txt` :
```
🤖 [Mike] Cadrage terminé — 100% des cas
Structure : {"type":"doc","version":1} et "guillemets"
Antislash \ et double \\ et tabulation	littérale
```

`fixtures/plain/vides.txt` :
```
Ligne un.

Ligne trois après une vide.


Ligne six après deux vides.
```

- [ ] **Étape 2 : écrire le générateur de références**

`plugins/ezacae-jira/tests/gen-fixtures.sh` :
```bash
#!/usr/bin/env bash
# Régénère les références de non-régression de jira_text_to_adf.
#
# ⚠️ À ne relancer QUE volontairement, en connaissance de cause : ces fichiers
# figent le comportement d'AVANT la mise en forme (RD-23). Les régénérer après
# une modification de la fonction rendrait le test de non-régression tautologique.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"

for f in "$HERE"/fixtures/plain/*.txt; do
  jira_text_to_adf < "$f" > "${f%.txt}.adf.json"
  echo "→ ${f%.txt}.adf.json"
done
```

- [ ] **Étape 3 : générer les références et vérifier qu'elles décrivent bien l'ancien comportement**

Run :
```bash
bash plugins/ezacae-jira/tests/gen-fixtures.sh
jq -r '[.content[].type] | unique | join(",")' plugins/ezacae-jira/tests/fixtures/plain/simple.adf.json
```
Attendu : `→ …` pour les quatre fichiers, puis `paragraph` (et rien d'autre — c'est la preuve que la référence est bien l'ancien comportement).

- [ ] **Étape 4 : commit**

```bash
git add plugins/ezacae-jira/tests/gen-fixtures.sh plugins/ezacae-jira/tests/fixtures/plain/
git commit -m "test(jira): figer les références de non-régression de jira_text_to_adf"
```

---

### Tâche 2 : test de non-régression et de sûreté littérale (caractérisation)

**Fichiers :**
- Créer : `plugins/ezacae-jira/tests/test_adf_write.sh`

**Interfaces :**
- Consomme : `jira_text_to_adf`, les références de la tâche 1
- Produit : `test_adf_write.sh`, enrichi par les tâches 4, 5, 6, 7

> Ces tests **passent dès l'écriture**. Ils protègent l'existant ; il n'y a pas d'étape rouge.

- [ ] **Étape 1 : écrire le test**

`plugins/ezacae-jira/tests/test_adf_write.sh` :
```bash
#!/usr/bin/env bash
# Tests de jira_text_to_adf — écriture texte → ADF (RD-23).
# 100% hors-ligne : n'exerce que la conversion, aucun appel réseau.
# Lancer : bash plugins/ezacae-jira/tests/test_adf_write.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"
PASS=0; FAIL=0

ok()   { echo "PASS  $1"; PASS=$((PASS+1)); }
nope() { echo "FAIL  $1"; FAIL=$((FAIL+1)); }

# --- Non-régression : sortie identique OCTET POUR OCTET aux références figées ---
for f in "$HERE"/fixtures/plain/*.txt; do
  label="non-régression $(basename "$f")"
  if jira_text_to_adf < "$f" | diff -q - "${f%.txt}.adf.json" >/dev/null; then
    ok "$label"
  else
    nope "$label"
    jira_text_to_adf < "$f" | diff - "${f%.txt}.adf.json" | head -10
  fi
done

# --- Sûreté littérale : notre vocabulaire traverse l'outil intact ---
# 3 invariants par ligne : texte identique, aucun mark, un seul paragraphe.
check_literal() {
  local label="$1" line="$2" adf text marks blocks
  adf=$(printf '%s' "$line" | jira_text_to_adf)
  text=$(printf '%s' "$adf" | jq -r '[.. | objects | select(.type=="text") | .text] | join("")')
  marks=$(printf '%s' "$adf" | jq '[.. | objects | select(has("marks"))] | length')
  blocks=$(printf '%s' "$adf" | jq -r '[.content[].type] | unique | join(",")')
  [ "$text" = "$line" ]     || { nope "$label — texte altéré : $text"; return; }
  [ "$marks" = "0" ]        || { nope "$label — $marks mark(s) sur du littéral"; return; }
  [ "$blocks" = "paragraph" ] || { nope "$label — blocs : $blocks"; return; }
  ok "$label"
}

check_literal "identifiants snake_case" \
  'jira_text_to_adf est appelée par jira_load_env et jira_require_creds'
check_literal "fichier de test du plugin" \
  'Modèle : plugins/ezacae-jira/tests/test_jira_guard.sh'
check_literal "deux globs doublés" \
  'changes: plugins/**/* et deploy/jira-watcher/**/*'
check_literal "multiplication et exposant" \
  'Coût : 2 * 3 = 6 opérations, complexité n**2'
check_literal "préfixe de passation et parenthèses" \
  '🤖 [Mike] Cadrage terminé (voir docs/conception/cadrage.md)'
check_literal "pathspec git" \
  "git restore -- . ':(exclude)node_modules'"
check_literal "JSON et antislash" \
  '🤖 {"type":"doc"} "guillemets" et \ antislash — 100%'
check_literal "shebang (un seul dièse)" \
  '#!/usr/bin/env bash'
check_literal "quatre dièses" \
  '#### pas un titre'
check_literal "marqueur de titre sans contenu" \
  '## '
check_literal "marqueur de puce sans contenu" \
  '- '
check_literal "puce indentée (pas d'\''imbrication)" \
  '  - élément indenté'
check_literal "puce sans espace après le tiret" \
  '-pas une puce'

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Étape 2 : lancer — tout doit passer sur le code actuel**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `Résultat : PASS=17 FAIL=0`

- [ ] **Étape 3 : commit**

```bash
git add plugins/ezacae-jira/tests/test_adf_write.sh
git commit -m "test(jira): non-régression et sûreté littérale de la conversion ADF"
```

---

### Tâche 3 : rendu de lecture — frontières de blocs et non-perte

**Fichiers :**
- Créer : `plugins/ezacae-jira/tests/test_adf_read.sh`
- Modifier : `plugins/ezacae-jira/scripts/jira-lib.sh` (ajout de `JIRA_JQ_ADF_RENDER`)
- Modifier : `plugins/ezacae-jira/scripts/jira-get.sh:37-57`

**Interfaces :**
- Produit : `JIRA_JQ_ADF_RENDER` — variable contenant un programme jq qui définit `adf_render`, applicable à un document ADF et retournant une chaîne. Utilisée par `jira-get.sh`.

- [ ] **Étape 1 : écrire le test qui échoue**

`plugins/ezacae-jira/tests/test_adf_read.sh` :
```bash
#!/usr/bin/env bash
# Tests du rendu ADF → texte lisible (RD-23, côté lecture).
# 100% hors-ligne : les documents ADF sont écrits à la main, aucun appel réseau.
# Lancer : bash plugins/ezacae-jira/tests/test_adf_read.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/jira-lib.sh"
PASS=0; FAIL=0

# render <doc-json> → texte rendu
render() { printf '%s' "$1" | jq -r "$JIRA_JQ_ADF_RENDER adf_render"; }

# expect_contains <label> <doc-json> <sous-chaîne attendue>
expect_contains() {
  local label="$1" doc="$2" want="$3" got
  got=$(render "$doc")
  if [[ "$got" == *"$want"* ]]; then
    echo "PASS  $label"; PASS=$((PASS+1))
  else
    echo "FAIL  $label — attendu «$want» dans :"; printf '%s\n' "$got" | sed 's/^/      /'
    FAIL=$((FAIL+1))
  fi
}

DOC_2P='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"text","text":"RD-17"}]},
  {"type":"paragraph","content":[{"type":"text","text":"PÉRIMÈTRE RÉEL"}]}]}'
expect_contains "deux paragraphes séparés par une ligne vide" \
  "$DOC_2P" 'RD-17

PÉRIMÈTRE RÉEL'

DOC_LIST='{"type":"doc","version":1,"content":[
  {"type":"bulletList","content":[
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"un"}]}]},
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"deux"}]}]}]}]}'
expect_contains "puces sur des lignes distinctes" "$DOC_LIST" '- un
- deux'

DOC_ORD='{"type":"doc","version":1,"content":[
  {"type":"orderedList","attrs":{"order":3},"content":[
    {"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"trois"}]}]}]}]}'
expect_contains "liste numérotée respectant attrs.order" "$DOC_ORD" '3. trois'

DOC_HEAD='{"type":"doc","version":1,"content":[
  {"type":"heading","attrs":{"level":2},"content":[{"type":"text","text":"Périmètre"}]}]}'
expect_contains "titre préfixé de ses dièses" "$DOC_HEAD" '## Périmètre'

DOC_CODE='{"type":"doc","version":1,"content":[
  {"type":"codeBlock","attrs":{"language":"bash"},"content":[{"type":"text","text":"set -e\nexit 0"}]}]}'
expect_contains "bloc de code encadré, langage conservé" "$DOC_CODE" '```bash
set -e
exit 0
```'

# --- Non-perte : le défaut observé sur RD-23 ---
DOC_CARD='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[
    {"type":"text","text":"The linked issue "},
    {"type":"inlineCard","attrs":{"url":"https://ezacae.atlassian.net/browse/RD-17"}},
    {"type":"text","text":" has been resolved"}]}]}'
expect_contains "carte de ticket liée : URL restituée" "$DOC_CARD" "browse/RD-17"

DOC_MENTION='{"type":"doc","version":1,"content":[
  {"type":"paragraph","content":[{"type":"mention","attrs":{"id":"x","text":"@Patrice"}}]}]}'
expect_contains "mention : texte restitué" "$DOC_MENTION" "@Patrice"

DOC_TABLE='{"type":"doc","version":1,"content":[
  {"type":"table","content":[{"type":"tableRow","content":[
    {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"clé"}]}]},
    {"type":"tableCell","content":[{"type":"paragraph","content":[{"type":"text","text":"valeur"}]}]}]}]}]}'
expect_contains "tableau : cellules restituées" "$DOC_TABLE" "clé"

DOC_UNKNOWN='{"type":"doc","version":1,"content":[
  {"type":"blocDuFutur","content":[
    {"type":"paragraph","content":[{"type":"text","text":"contenu inconnu"}]}]}]}'
expect_contains "type inconnu : rien n'"'"'est jeté" "$DOC_UNKNOWN" "contenu inconnu"

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bash plugins/ezacae-jira/tests/test_adf_read.sh`
Attendu : ÉCHEC — `JIRA_JQ_ADF_RENDER: unbound variable` ou `FAIL` sur les neuf cas.

- [ ] **Étape 3 : ajouter le programme de rendu dans `jira-lib.sh`**

À insérer dans `jira-lib.sh`, dans la section `--- ADF ---`, avant `jira_text_to_adf` :
```bash
# Programme jq définissant `adf_render` : un document ADF → texte lisible.
# Deux exigences : rendre les frontières de blocs visibles, et ne JAMAIS jeter
# de contenu (tout type inconnu retombe sur une extraction récursive du texte).
# Stocké en variable : ce fichier ne doit rien exécuter ni rien écrire au
# chargement (le hook jira-guard.sh lit son propre stdout comme du JSON).
JIRA_JQ_ADF_RENDER='
  def adf_inline:
    if type == "array" then map(adf_inline) | join("")
    elif type != "object" then ""
    elif .type == "text" then (.text // "")
    elif .type == "hardBreak" then "\n"
    elif (.attrs.text? // null) != null then .attrs.text
    elif (.attrs.url? // null) != null then .attrs.url
    elif (.attrs.shortName? // null) != null then .attrs.shortName
    elif .content? then (.content | adf_inline)
    else "" end;

  def indent($n): split("\n") | map(($n * " ") + .) | join("\n");

  def adf_block:
    if type != "object" then ""
    elif .type == "paragraph" then (.content // [] | adf_inline)
    elif .type == "heading" then
      (((.attrs.level // 1) * "#") + " " + (.content // [] | adf_inline))
    elif .type == "codeBlock" then
      ("```" + (.attrs.language // "") + "\n" + (.content // [] | adf_inline) + "\n```")
    elif .type == "rule" then "---"
    elif .type == "blockquote" then
      ((.content // [] | map(adf_block) | join("\n")) | split("\n") | map("> " + .) | join("\n"))
    elif .type == "bulletList" then
      (.content // [] | map("- " + ((.content // [] | map(adf_block) | join("\n")) | indent(2) | ltrimstr("  "))) | join("\n"))
    elif .type == "orderedList" then
      ((.attrs.order // 1) as $start
       | .content // [] | to_entries
       | map((($start + .key) | tostring) + ". "
             + ((.value.content // [] | map(adf_block) | join("\n")) | indent(3) | ltrimstr("   ")))
       | join("\n"))
    elif .type == "table" then
      (.content // [] | map(
         "| " + ((.content // []) | map(adf_inline) | join(" | ")) + " |") | join("\n"))
    elif .content? then (.content | map(adf_block) | join("\n"))
    else adf_inline end;

  # Les blocs vides sont écartés AVANT le join : les lignes vides du texte
  # source produisent des paragraphes vides, qui doubleraient les séparations
  # (vérifié en bac à sable : trois lignes blanches entre chaque bloc sinon).
  def adf_render: (.content // []) | map(adf_block) | map(select(. != "")) | join("\n\n");
'
```

> **Invocation.** `JIRA_JQ_ADF_RENDER` se termine par un `;` : le corps du programme se concatène **sans barre verticale**. `jq -r "$JIRA_JQ_ADF_RENDER adf_render"` fonctionne, `jq -r "$JIRA_JQ_ADF_RENDER"' | adf_render'` échoue avec `syntax error, unexpected '|'`.

- [ ] **Étape 4 : lancer le test — il doit passer**

Run : `bash plugins/ezacae-jira/tests/test_adf_read.sh`
Attendu : `Résultat : PASS=9 FAIL=0`

- [ ] **Étape 5 : brancher `jira-get.sh` sur le rendu partagé**

Dans `jira-get.sh`, remplacer le bloc `l. 37-49` par :
```bash
# Rendu ADF partagé (jira-lib.sh) : frontières de blocs visibles, aucune perte.
JQ_SUMMARY="$JIRA_JQ_ADF_RENDER"'
  "🎫 \(.key)  [\(.fields.status.name // "?")]  \(.fields.issuetype.name // "")",
  "Résumé    : \(.fields.summary // "")",
  "Assigné   : \(.fields.assignee.displayName // "non assigné")",
  "Priorité  : \(.fields.priority.name // "")",
  "Labels    : \((.fields.labels // []) | join(", "))",
  "",
  "--- Description ---",
  (.fields.description | if . == null then "(vide)" else adf_render end)
'
printf '%s' "$DATA" | jq -r "$JQ_SUMMARY"
```

et le bloc `l. 51-58` par :
```bash
if [ "$WITH_COMMENTS" = "1" ]; then
  JQ_COMMENTS="$JIRA_JQ_ADF_RENDER"'
    "", "--- Commentaires (\(.fields.comment.total // 0)) ---",
    (.fields.comment.comments[]? | "• [\(.author.displayName // "?")] \(.created[0:16])\n\(.body | adf_render)\n")
  '
  printf '%s' "$DATA" | jq -r "$JQ_COMMENTS"
fi
```

- [ ] **Étape 6 : vérifier sur un vrai ticket (seule étape en ligne du plan)**

Run : `plugins/ezacae-jira/scripts/jira-get.sh RD-23 --comments`
Attendu : les paragraphes de la description sont séparés par des lignes vides ; plus de `DEMANDENos` ; le commentaire d'Automation affiche l'URL du ticket lié au lieu de `issue -  has`.

- [ ] **Étape 7 : commit**

```bash
git add plugins/ezacae-jira/scripts/jira-lib.sh plugins/ezacae-jira/scripts/jira-get.sh \
        plugins/ezacae-jira/tests/test_adf_read.sh
git commit -m "fix(jira): restituer les frontières de blocs à la lecture, sans perte de contenu"
```

---

### Tâche 4 : écriture — titres

**Fichiers :**
- Modifier : `plugins/ezacae-jira/scripts/jira-lib.sh` (`jira_text_to_adf`, l. 107-117)
- Modifier : `plugins/ezacae-jira/tests/test_adf_write.sh`

**Interfaces :**
- Produit : `JIRA_JQ_TEXT_TO_ADF` — programme jq consommé par `jira_text_to_adf` via `jq -Rs`. `JIRA_JQ_TEXT_TO_ADF_FLAT` conserve **mot pour mot** le programme actuel, utilisé comme repli par la tâche 6.

- [ ] **Étape 1 : écrire le test qui échoue**

À ajouter dans `test_adf_write.sh`, avant le bloc `echo "----"` :
```bash
# --- Constructions promues ---
# expect_shape <label> <texte> <programme jq booléen>
expect_shape() {
  local label="$1" txt="$2" prog="$3"
  if printf '%s' "$txt" | jira_text_to_adf | jq -e "$prog" >/dev/null 2>&1; then
    ok "$label"
  else
    nope "$label"
    printf '%s' "$txt" | jira_text_to_adf | head -20 | sed 's/^/      /'
  fi
}

expect_shape "## produit un heading de niveau 2" '## Périmètre' \
  '.content|length==1 and .content[0].type=="heading" and .content[0].attrs.level==2
   and .content[0].content[0].text=="Périmètre"'
expect_shape "### produit un heading de niveau 3" '### Détail' \
  '.content[0].type=="heading" and .content[0].attrs.level==3'
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `FAIL  ## produit un heading de niveau 2` et `FAIL  ### …`, les 17 tests précédents toujours en PASS.

- [ ] **Étape 3 : remplacer `jira_text_to_adf` par la version à état**

Remplacer `jira-lib.sh` l. 107-117 par :
```bash
# --- ADF (Atlassian Document Format) ------------------------------------------
#
# (JIRA_JQ_ADF_RENDER est défini plus haut : lecture.)

# Programme jq d'origine (RD-15) : une ligne = un paragraphe. Conservé mot pour
# mot comme repli — c'est lui qui garantit qu'un envoi aboutit toujours (RD-23).
JIRA_JQ_TEXT_TO_ADF_FLAT='{type:"doc",version:1,content:(
    rtrimstr("\n") | split("\n") |
    map(if . == "" then {type:"paragraph"}
        else {type:"paragraph",content:[{type:"text",text:.}]} end)
  )}'

# Convertisseur ORIENTÉ LIGNE (RD-23). Ne promeut que les constructions ancrées
# en début de ligne : titres, listes, blocs de code. Aucune recherche de paires
# de signes au milieu des phrases — nos textes sont pleins de noms de fichiers
# et de chemins que cela corromprait en silence. Toute ligne non reconnue
# redevient un paragraphe, à l identique de JIRA_JQ_TEXT_TO_ADF_FLAT.
JIRA_JQ_TEXT_TO_ADF='
  def para($s): if $s == "" then {type:"paragraph"}
                else {type:"paragraph",content:[{type:"text",text:$s}]} end;
  def heading($lvl; $s): {type:"heading",attrs:{level:$lvl},content:[{type:"text",text:$s}]};

  rtrimstr("\n") | split("\n")
  | reduce .[] as $line ({out:[]};
      ($line | capture("^(?<h>#{2,3}) (?<t>\\S.*)$") // null) as $head
      | if $head != null then
          .out += [heading(($head.h|length); $head.t)]
        else
          .out += [para($line)]
        end)
  | {type:"doc",version:1,content:.out}
'

# Convertit du texte multi-lignes (stdin) en document ADF sur stdout.
jira_text_to_adf() {
  jq -Rs "$JIRA_JQ_TEXT_TO_ADF"
}
```

- [ ] **Étape 4 : lancer — tout doit passer**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `Résultat : PASS=19 FAIL=0`. Les quatre non-régressions octet pour octet **doivent** rester en PASS : si l'une tombe, l'ordre des clés ou le retour à la ligne final a changé.

- [ ] **Étape 5 : commit**

```bash
git add plugins/ezacae-jira/scripts/jira-lib.sh plugins/ezacae-jira/tests/test_adf_write.sh
git commit -m "feat(jira): promouvoir les lignes ## et ### en titres ADF"
```

---

### Tâche 5 : écriture — listes à puces et numérotées

**Fichiers :**
- Modifier : `plugins/ezacae-jira/scripts/jira-lib.sh` (`JIRA_JQ_TEXT_TO_ADF`)
- Modifier : `plugins/ezacae-jira/tests/test_adf_write.sh`

**Interfaces :**
- Consomme : `JIRA_JQ_TEXT_TO_ADF` de la tâche 4
- Produit : le même programme, avec regroupement des éléments consécutifs

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `test_adf_write.sh`, après les tests de titres :
```bash
expect_shape "deux puces consécutives = une seule bulletList" \
  '- un
- deux' \
  '.content|length==1 and .content[0].type=="bulletList"
   and (.content[0].content|length==2)
   and .content[0].content[0].type=="listItem"
   and .content[0].content[0].content[0].type=="paragraph"
   and .content[0].content[0].content[0].content[0].text=="un"'

expect_shape "un paragraphe ferme la liste" \
  '- un
suite' \
  '[.content[].type] == ["bulletList","paragraph"]'

expect_shape "une ligne vide ferme la liste et reste un paragraphe vide" \
  '- un

- deux' \
  '[.content[].type] == ["bulletList","paragraph","bulletList"]
   and (.content[1] | has("content") | not)'

expect_shape "liste numérotée démarrant à 1 : pas d'\''attrs" \
  '1. un
2. deux' \
  '.content[0].type=="orderedList" and (.content[0]|has("attrs")|not)
   and (.content[0].content|length==2)'

expect_shape "liste numérotée démarrant à 3 : attrs.order=3" \
  '3. trois' \
  '.content[0].type=="orderedList" and .content[0].attrs.order==3'
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `FAIL` sur les cinq nouveaux cas, PASS sur les 19 précédents.

- [ ] **Étape 3 : ajouter le regroupement des listes**

Remplacer la valeur de `JIRA_JQ_TEXT_TO_ADF` par :
```bash
JIRA_JQ_TEXT_TO_ADF='
  def para($s): if $s == "" then {type:"paragraph"}
                else {type:"paragraph",content:[{type:"text",text:$s}]} end;
  def heading($lvl; $s): {type:"heading",attrs:{level:$lvl},content:[{type:"text",text:$s}]};
  def item($s): {type:"listItem",content:[para($s)]};

  # Referme la liste en cours (si elle existe) et la verse dans .out.
  def flush:
    if .mode == "bullet" then
      .out += [{type:"bulletList",content:.buf}] | .mode = "none" | .buf = []
    elif .mode == "ordered" then
      .out += [ {type:"orderedList"}
                + (if .order == 1 then {} else {attrs:{order:.order}} end)
                + {content:.buf} ]
      | .mode = "none" | .buf = []
    else . end;

  rtrimstr("\n") | split("\n")
  | reduce .[] as $line ({out:[], mode:"none", buf:[], order:1};
      ($line | capture("^(?<h>#{2,3}) (?<t>\\S.*)$") // null) as $head
      | ($line | capture("^- (?<t>\\S.*)$") // null) as $bul
      | ($line | capture("^(?<n>[0-9]+)\\. (?<t>\\S.*)$") // null) as $ord
      | if $head != null then flush | .out += [heading(($head.h|length); $head.t)]
        elif $bul != null then
          (if .mode == "bullet" then . else flush | .mode = "bullet" end)
          | .buf += [item($bul.t)]
        elif $ord != null then
          (if .mode == "ordered" then . else flush | .mode = "ordered" | .order = ($ord.n|tonumber) end)
          | .buf += [item($ord.t)]
        else flush | .out += [para($line)]
        end)
  | flush
  | {type:"doc",version:1,content:.out}
'
```

- [ ] **Étape 4 : lancer — tout doit passer**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `Résultat : PASS=24 FAIL=0`, non-régressions incluses.

- [ ] **Étape 5 : commit**

```bash
git add plugins/ezacae-jira/scripts/jira-lib.sh plugins/ezacae-jira/tests/test_adf_write.sh
git commit -m "feat(jira): regrouper les lignes - et 1. en bulletList / orderedList"
```

---

### Tâche 6 : écriture — blocs de code et filet de sécurité

**Fichiers :**
- Modifier : `plugins/ezacae-jira/scripts/jira-lib.sh` (`JIRA_JQ_TEXT_TO_ADF`, ajout de `JIRA_JQ_ADF_VALID`, réécriture de `jira_text_to_adf`)
- Modifier : `plugins/ezacae-jira/tests/test_adf_write.sh`

**Interfaces :**
- Produit : `JIRA_JQ_ADF_VALID` — programme jq booléen appliqué à un document ADF, vrai si les cinq invariants de validité tiennent. `jira_text_to_adf` l'utilise pour décider du repli.

- [ ] **Étape 1 : écrire les tests qui échouent**

À ajouter dans `test_adf_write.sh` :
```bash
expect_shape "bloc de code avec langage" \
  '```bash
set -e
exit 0
```' \
  '.content|length==1 and .content[0].type=="codeBlock"
   and .content[0].attrs.language=="bash"
   and .content[0].content[0].text=="set -e\nexit 0"'

expect_shape "rien n'\''est promu à l'\''intérieur d'\''un bloc de code" \
  '```
## pas un titre
- pas une puce
```' \
  '.content|length==1 and .content[0].type=="codeBlock"
   and (.content[0]|has("attrs")|not)
   and .content[0].content[0].text=="## pas un titre\n- pas une puce"'

expect_shape "bloc de code vide : pas de nœud texte vide" \
  '```
```' \
  '.content[0].type=="codeBlock" and (.content[0]|has("content")|not)'

expect_shape "bloc jamais fermé : dégradation en paragraphes, ordre conservé" \
  '```bash
set -e' \
  '[.content[].type] == ["paragraph","paragraph"]
   and .content[0].content[0].text=="```bash"
   and .content[1].content[0].text=="set -e"'

# --- Validité structurelle : tous les cas produisent un ADF valide ---
expect_valid() {
  local label="$1" txt="$2"
  if printf '%s' "$txt" | jira_text_to_adf | jq -e "$JIRA_JQ_ADF_VALID" >/dev/null 2>&1; then
    ok "validité — $label"
  else
    nope "validité — $label"
  fi
}
expect_valid "document mixte" '## Titre

- un
- deux

1. étape

```sh
echo ok
```
Fin.'
expect_valid "corpus json-hostile" "$(cat "$HERE/fixtures/plain/json-hostile.txt")"
```

- [ ] **Étape 2 : lancer pour vérifier l'échec**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `FAIL` sur les six nouveaux cas (dont `JIRA_JQ_ADF_VALID: unbound variable` sur les deux derniers).

- [ ] **Étape 3 : ajouter les blocs de code au convertisseur**

Dans `JIRA_JQ_TEXT_TO_ADF`, ajouter la définition de `code` après `item`, et l'état de bloc au `reduce` :
```bash
  def code($lang; $lines):
    {type:"codeBlock"}
    + (if $lang == "" then {} else {attrs:{language:$lang}} end)
    + (if ($lines|length) == 0 then {} else {content:[{type:"text",text:($lines|join("\n"))}]} end);
```

Dans `flush`, ajouter la branche du bloc **non fermé** (dégradation) :
```bash
    elif .mode == "fence" then
      .out += ([para(.raw)] + (.buf | map(para(.)))) | .mode = "none" | .buf = [] | .raw = ""
```

Dans le `reduce`, en **tout premier test** (priorité maximale) :
```bash
      | ($line | capture("^```(?<lang>.*)$") // null) as $fence
      | if .mode == "fence" then
          (if ($line | test("^```\\s*$")) then
             .out += [code(.lang; .buf)] | .mode = "none" | .buf = [] | .lang = "" | .raw = ""
           else .buf += [$line] end)
        elif $fence != null then
          flush | .mode = "fence" | .buf = [] | .lang = ($fence.lang | ltrimstr(" ") | rtrimstr(" ")) | .raw = $line
        elif $head != null then …
```
L'état initial du `reduce` devient `{out:[], mode:"none", buf:[], order:1, lang:"", raw:""}`.

- [ ] **Étape 4 : ajouter les invariants de validité**

Dans `jira-lib.sh`, avant `jira_text_to_adf` :
```bash
# Invariants de validité ADF vérifiables hors-ligne (sous-ensemble couvrant nos
# erreurs possibles, pas le schéma officiel de Jira). Booléen sur stdout.
JIRA_JQ_ADF_VALID='
  ([.. | objects | select(.type=="text") | select((.text // "") == "")] | length) == 0
  and ([.. | objects | select(.type=="listItem") | (.content // [])[]
        | select((.type // "") as $t
                 | ($t=="paragraph" or $t=="bulletList" or $t=="orderedList") | not)]
       | length) == 0
  and ([.. | objects | select(.type=="bulletList" or .type=="orderedList")
        | (.content // [])[] | select(.type != "listItem")] | length) == 0
  and ([.. | objects | select(.type=="heading")
        | select(((.attrs.level // 0) | (. >= 1 and . <= 6)) | not)] | length) == 0
  and ([.. | objects | select(.type=="codeBlock") | (.content // [])[]
        | select(.type != "text" or has("marks"))] | length) == 0
'
```

- [ ] **Étape 5 : brancher le filet de sécurité**

Remplacer la fonction par :
```bash
# Convertit du texte multi-lignes (stdin) en document ADF sur stdout.
#
# Filet de sécurité (RD-23) : si la structure produite viole les invariants de
# validité, on replie sur la conversion plate d'origine plutôt que de risquer un
# refus de l'API. Un envoi ne doit JAMAIS échouer à cause de la mise en forme —
# dans jira-transition.sh, le commentaire part après la transition : un refus
# laisserait le ticket transitionné sans passation, sans possibilité de rejouer.
jira_text_to_adf() {
  local input adf
  input=$(cat)
  adf=$(printf '%s' "$input" | jq -Rs "$JIRA_JQ_TEXT_TO_ADF")
  if printf '%s' "$adf" | jq -e "$JIRA_JQ_ADF_VALID" >/dev/null 2>&1; then
    printf '%s\n' "$adf"
  else
    echo "⚠️  Structure ADF invalide — repli sur la conversion plate." >&2
    printf '%s' "$input" | jq -Rs "$JIRA_JQ_TEXT_TO_ADF_FLAT"
  fi
}
```

> `$(...)` supprime les retours à la ligne finaux, d'où le `printf '%s\n'` : jq en émet exactement un, et la non-régression octet pour octet en dépend.

- [ ] **Étape 6 : lancer — tout doit passer**

Run : `bash plugins/ezacae-jira/tests/test_adf_write.sh`
Attendu : `Résultat : PASS=30 FAIL=0`.

- [ ] **Étape 7 : commit**

```bash
git add plugins/ezacae-jira/scripts/jira-lib.sh plugins/ezacae-jira/tests/test_adf_write.sh
git commit -m "feat(jira): blocs de code et repli sur conversion plate si structure invalide"
```

---

### Tâche 7 : aller-retour sur un texte de référence

**Fichiers :**
- Créer : `plugins/ezacae-jira/tests/fixtures/reference.md`
- Modifier : `plugins/ezacae-jira/tests/test_adf_read.sh`

**Interfaces :**
- Consomme : `jira_text_to_adf` (tâches 4-6), `JIRA_JQ_ADF_RENDER` (tâche 3)

- [ ] **Étape 1 : écrire le texte de référence**

`plugins/ezacae-jira/tests/fixtures/reference.md` :
```
## Périmètre retenu

Écriture — uniquement les constructions ancrées en début de ligne.

- titres
- listes à puces
- listes numérotées
- blocs de code

Étapes :

1. figer les références
2. corriger la lecture
3. corriger l'écriture

Vérification :

```bash
bash plugins/ezacae-jira/tests/test_adf_write.sh
```

### Hors périmètre

Gras, italique et liens. Un chemin comme plugins/**/* doit rester intact.
```

- [ ] **Étape 2 : écrire le test d'aller-retour**

À ajouter dans `test_adf_read.sh`, avant `echo "----"` :
```bash
# --- Aller-retour : écriture puis lecture d'un texte couvrant les 4 constructions ---
ROUND=$(jira_text_to_adf < "$HERE/fixtures/reference.md" | jq -r "$JIRA_JQ_ADF_RENDER adf_render")

roundtrip() {
  local label="$1" want="$2"
  if [[ "$ROUND" == *"$want"$'\n'* || "$ROUND" == *"$want" ]]; then
    echo "PASS  aller-retour — $label"; PASS=$((PASS+1))
  else
    echo "FAIL  aller-retour — $label (absent : «$want»)"; FAIL=$((FAIL+1))
  fi
}
roundtrip "titre de niveau 2"      '## Périmètre retenu'
roundtrip "titre de niveau 3"      '### Hors périmètre'
roundtrip "puce"                   '- listes numérotées'
roundtrip "numéro"                 '2. corriger la lecture'
roundtrip "ouverture de bloc"      '```bash'
roundtrip "glob intact"            'Gras, italique et liens. Un chemin comme plugins/**/* doit rester intact.'

# Aucun bloc collé : jamais deux blocs sans séparation.
if printf '%s' "$ROUND" | grep -q 'retenuÉcriture'; then
  echo "FAIL  aller-retour — blocs collés"; FAIL=$((FAIL+1))
else
  echo "PASS  aller-retour — blocs séparés"; PASS=$((PASS+1))
fi

# Séparation SIMPLE : les paragraphes vides du texte source ne doivent pas
# doubler les lignes blanches (défaut constaté en bac à sable, cf. adf_render).
# Compté en awk, pas en grep : grep découpe son motif sur les retours à la
# ligne, donc un motif « \n\n\n » devient des motifs vides qui matchent tout
# (piège rencontré à l'implémentation — le test échouait sur du code correct).
MAXBLANK=$(printf '%s\n' "$ROUND" \
  | awk 'BEGIN{m=0;c=0} /^$/{c++; if(c>m)m=c; next} {c=0} END{print m}')
if [ "$MAXBLANK" -le 1 ]; then
  echo "PASS  aller-retour — une seule ligne blanche entre blocs"; PASS=$((PASS+1))
else
  echo "FAIL  aller-retour — $MAXBLANK lignes blanches consécutives"; FAIL=$((FAIL+1))
fi
```

- [ ] **Étape 3 : lancer**

Run : `bash plugins/ezacae-jira/tests/test_adf_read.sh`
Attendu : `Résultat : PASS=16 FAIL=0`

- [ ] **Étape 4 : commit**

```bash
git add plugins/ezacae-jira/tests/fixtures/reference.md plugins/ezacae-jira/tests/test_adf_read.sh
git commit -m "test(jira): aller-retour écriture/lecture sur un texte de référence"
```

---

### Tâche 8 : non-régression du hook et des tests existants

**Fichiers :**
- Modifier : `plugins/ezacae-jira/tests/test_adf_write.sh`

- [ ] **Étape 1 : écrire le test de silence au chargement**

À ajouter dans `test_adf_write.sh` :
```bash
# --- Le hook jira-guard.sh lit son propre stdout comme du JSON : la
# bibliothèque ne doit RIEN écrire au chargement (jira-lib.sh:8-9).
LOAD_OUT=$(bash -c '. "'"$HERE"'/../scripts/jira-lib.sh"' 2>/dev/null)
if [ -z "$LOAD_OUT" ]; then
  ok "jira-lib.sh est muet au chargement"
else
  nope "jira-lib.sh écrit au chargement : $LOAD_OUT"
fi
```

- [ ] **Étape 2 : lancer les trois suites**

Run :
```bash
bash plugins/ezacae-jira/tests/test_jira_guard.sh
bash plugins/ezacae-jira/tests/test_adf_write.sh
bash plugins/ezacae-jira/tests/test_adf_read.sh
```
Attendu : `FAIL=0` sur les trois. La garde de statut est inchangée : `test_jira_guard.sh` doit afficher exactement le même total qu'avant le ticket.

- [ ] **Étape 3 : commit**

```bash
git add plugins/ezacae-jira/tests/test_adf_write.sh
git commit -m "test(jira): garantir le silence de jira-lib.sh au chargement"
```

---

### Tâche 9 : job d'intégration continue pour les tests shell

**Fichiers :**
- Modifier : `.gitlab-ci.yml`

Aucun job ne lance les tests shell aujourd'hui : la garantie de ce ticket ne survivrait pas au premier oubli. Le job vit dans le stage intégré `.pre` pour ne pas redéfinir la clé `stages` du template commun inclus — même précaution que le job existant, qui la documente déjà.

- [ ] **Étape 1 : ajouter le job**

À la fin de `.gitlab-ci.yml` :
```yaml
# ---------------------------------------------------------------------------
# Tests shell des plugins (bash + jq, 100% hors-ligne, aucun credential requis).
# Stage `.pre` intégré : ne redéfinit pas la clé `stages` du template commun.
# ---------------------------------------------------------------------------
test-plugins-shell:
  stage: .pre
  image: alpine:3.20
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes: &plugin_shell_changes
        - plugins/**/*
        - .gitlab-ci.yml
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      changes: *plugin_shell_changes
  before_script:
    - apk add --no-cache bash jq
  script:
    - |
      status=0
      for t in plugins/*/tests/test_*.sh; do
        echo "=== $t"
        bash "$t" || status=1
      done
      exit $status
```

- [ ] **Étape 2 : vérifier la syntaxe et le comportement en local**

Run :
```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.gitlab-ci.yml')); print('YAML valide')"
status=0; for t in plugins/*/tests/test_*.sh; do echo "=== $t"; bash "$t" || status=1; done; echo "status=$status"
```
Attendu : `YAML valide`, puis chaque suite avec `FAIL=0` et `status=0`. Les tests `test-*.sh` (tiret) des plugins `ezacae-dev` et `ezacae-doc` ne sont pas captés par le motif `test_*.sh` — c'est volontaire, ce ticket n'a pas vocation à les faire entrer dans la CI.

- [ ] **Étape 3 : commit**

```bash
git add .gitlab-ci.yml
git commit -m "ci: lancer les tests shell des plugins sur MR et branche par défaut"
```

---

### Tâche 10 : vérification d'acceptation par Jira et merge request

L'acceptation par l'API ne peut pas être prouvée hors-ligne. Elle se vérifie une fois, à la main, et la preuve est collée dans la merge request.

- [ ] **Étape 1 : envoyer le texte de référence sur le ticket**

Run :
```bash
plugins/ezacae-jira/scripts/jira-comment.sh RD-23 -f plugins/ezacae-jira/tests/fixtures/reference.md
```
Attendu : `💬 commentaire ajouté à RD-23`, sans avertissement de repli sur stderr.

- [ ] **Étape 2 : relire et vérifier les deux bouts**

Run : `plugins/ezacae-jira/scripts/jira-get.sh RD-23 --comments | tail -40`
Attendu : titres préfixés de dièses, puces sur des lignes distinctes, bloc de code encadré, blocs séparés par des lignes vides, `plugins/**/*` intact. Vérifier aussi le rendu dans l'interface web : vrais titres, vraies puces, bloc de code encadré.

- [ ] **Étape 3 : pousser et ouvrir la merge request**

```bash
git push -u origin "$(git branch --show-current)"
```
Puis créer la MR (`glab mr create` ou l'interface GitLab), en collant dans la description : la sortie des trois suites de tests, la sortie du `jira-get.sh` de l'étape 2, et une capture du rendu web.

---

## Auto-revue

**Couverture du cadrage.** Écriture des quatre constructions : tâches 4-6. Exclusion du gras/italique/liens : garantie par les tests de sûreté littérale de la tâche 2, pas seulement par l'absence de code. Frontières de blocs à la lecture : tâche 3. Non-perte de contenu : tâche 3, étape 1 (cartes, mentions, tableaux, type inconnu). Non-régression au caractère près : tâches 1-2, revérifiée à chaque tâche suivante. Dégradation propre : tâche 6 (bloc non fermé) et tâche 2 (marqueurs seuls, quatre dièses, puce indentée). Envoi jamais en échec : filet de sécurité, tâche 6. Tests hors-ligne : toutes les suites ; les deux seules étapes en ligne du plan sont explicitement signalées (tâche 3 étape 6, tâche 10). Silence au chargement : tâche 8. Absence de CI : tâche 9. Ordre imposé pour les références : tâche 1, isolée et sans autre modification.

**Cohérence des noms.** `JIRA_JQ_ADF_RENDER` (tâche 3), `JIRA_JQ_TEXT_TO_ADF_FLAT` et `JIRA_JQ_TEXT_TO_ADF` (tâche 4), `JIRA_JQ_ADF_VALID` (tâche 6) — mêmes noms dans les définitions et dans tous les usages. Fonctions jq : `adf_inline`, `indent`, `adf_block`, `adf_render` côté lecture ; `para`, `heading`, `item`, `code`, `flush` côté écriture.

**Un seul périmètre.** L'outillage Jira du plugin `ezacae-jira`. La rédaction des textes (gabarits Mike/Sarah) est explicitement renvoyée au ticket compagnon.

**Ce qui a été exécuté avant validation.** Les deux programmes jq ont été éprouvés en bac à sable, hors du dépôt (aucune source modifiée, HARD-GATE respecté). Vérifié : la machine à états de l'écriture sur un texte mixte (titre, puces, numéros démarrant à 3, bloc de code, paragraphes) ; l'absence de promotion à l'intérieur d'un bloc de code ; la dégradation d'un bloc non fermé en paragraphes dans l'ordre ; le bloc vide sans nœud texte ; les dix cas de sûreté littérale ; l'égalité **octet pour octet** avec la conversion actuelle sur un texte sans syntaxe ; les cinq invariants de validité ; et côté lecture les cartes de ticket, mentions, tableaux, types inconnus et la séparation des paragraphes.

Deux défauts ont été trouvés et corrigés dans ce document grâce à ces essais : les lignes blanches doublées à la lecture (d'où le `map(select(. != ""))` dans `adf_render`) et l'invocation jq avec une barre verticale de trop.

**Ce qui n'a pas été exécuté :** l'intégration dans `jira-get.sh`, le filet de sécurité en bash, le job d'intégration continue, et l'acceptation par l'API Jira (tâche 10).

**Le contrat, ce sont les tests.** Si un programme jq ne passe pas un test, c'est le programme qu'on corrige, jamais le test. Les totaux annoncés (`PASS=17`, `19`, `24`, `30`, `9`, `16`) sont à recompter à l'exécution : ils servent de repère, pas de vérité.
