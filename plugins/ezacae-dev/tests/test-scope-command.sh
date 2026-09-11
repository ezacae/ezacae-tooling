#!/usr/bin/env bash
# Test de structure de la commande /scope (RD-44, spec brique 1 §2).
#
# /scope est une page de consignes, pas du code : ce test vérifie ce qui se
# vérifie sans lancer un modèle — la page existe, ne se déclenche jamais seule,
# tient sur une page, nomme les cinq étapes du sprint 1, passe par nos scripts
# Jira, s'arrête à « à valider » sans franchir la porte, et n'appelle ni
# brainstorming ni une autre méthode superpowers (rien ne se déclenche seul).
#
# Compatible bash 3.2. Aucune dépendance. Aucun accès réseau.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="$DIR/../commands/scope.md"
MAX_LIGNES=90

pass=0; fail=0
ok()   { echo "PASS: $1"; pass=$((pass+1)); }
nope() { echo "FAIL: $1"; fail=$((fail+1)); }
contient()  { grep -qiE -- "$2" "$CMD" && ok "$1" || nope "$1 — motif absent : $2"; }
absent()    { grep -qiE -- "$2" "$CMD" && nope "$1 — motif présent : $2" || ok "$1"; }

[ -f "$CMD" ] || { nope "commands/scope.md existe"; echo "-----"; echo "PASS=$pass FAIL=$fail"; exit 1; }
ok "commands/scope.md existe"

# --- Frontmatter : ne se déclenche jamais seul ------------------------------------
front=$(awk 'NR==1 && $0!="---"{exit} NR>1 && $0=="---"{exit} NR>1{print}' "$CMD")
printf '%s\n' "$front" | grep -qE '^disable-model-invocation: *true' \
  && ok "frontmatter : disable-model-invocation: true" \
  || nope "frontmatter : disable-model-invocation: true manquant"
printf '%s\n' "$front" | grep -qE '^description:' \
  && ok "frontmatter : description présente" || nope "frontmatter : description absente"

# --- Une page ---------------------------------------------------------------------
n=$(wc -l < "$CMD" | tr -d ' ')
[ "$n" -le "$MAX_LIGNES" ] && ok "une page : $n lignes (≤ $MAX_LIGNES)" || nope "trop long : $n lignes (> $MAX_LIGNES)"

# --- Les cinq étapes du sprint 1 (spec §2 : 1, 2, 3, 4, 6) ------------------------
contient "étape 1 : créer ou reprendre l'épique" "épique existante|reprend"
contient "étape 1 : création via jira-create.sh" "jira-create\.sh"
contient "étape 2 : demander d'abord si un document du besoin existe" "document.*(spécification|cahier|notes)|(spécification|cahier|notes).*document"
contient "étape 2 : lire ce document en entier avant la première question" "en entier"
contient "étape 2 : ne poser que ce que le document laisse ouvert" "laisse ouvert"
contient "étape 2 : questions par séries, via grilling" "grilling"
contient "étape 2 : réponse recommandée" "recommand"
contient "étape 3 : page de cadrage dans docs/conception" "docs/conception"
contient "étape 3 : lien dans l'épique" "lien"
contient "étape 4 : taille S, M, L, sans développement" "sans développement"
contient "étape 4 : étiquette posée via jira-edit.sh --label" "jira-edit\.sh .*--label"
contient "étape 4 : un L s'arrête après le cadrage" "\bL\b.*s'arrête|s'arrête.*\bL\b"
contient "étape 6 : passage en Conception validation" "CONCEPTION VALIDATION|Conception validation"
contient "étape 6 : la commande s'arrête" "s'arrête"

# --- Porte et garde-fous ----------------------------------------------------------
contient "la porte : seul le responsable produit clique" "responsable produit"
contient "la porte : nos scripts la refusent (RD-43)" "refus"
contient "le type d'épique se vérifie avant de créer" "avant de créer"
contient "vérification : un ticket existant du même type est cherché" "jira-search\.sh"
contient "vérification : ses transitions sont lues sans rien changer" "jira-transition\.sh .*--list"
contient "vérification : sans circuit, rien n'est créé" "rien n'est créé|ne crée rien"
contient "hors sprint : pas de page de spécification (RD-45)" "RD-45|spécification fonctionnelle"
absent   "aucun appel à brainstorming" "brainstorming"
absent   "aucune méthode superpowers" "superpowers"
absent   "aucun MCP" "mcp__|MCP Atlassian"
absent   "aucune sous-tâche créée" "sous-tâche|sub-task"

echo "-----"; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
