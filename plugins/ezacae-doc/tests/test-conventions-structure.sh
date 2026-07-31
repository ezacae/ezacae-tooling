#!/usr/bin/env bash
#
# test-conventions-structure.sh — garde-fou de la structure documentaire (RD-17).
#
# Invariant : l'ensemble des documents prescrits par la section « Structure
# documentaire par projet » de ezacae-base/conventions.md doit être EXACTEMENT
# l'ensemble des documents productibles par le plugin ezacae-doc.
#
#   - Prescrit mais non productible → l'audit /mike Phase 2 le signale
#     « ⬜ Manquant » à perpétuité, sur tous les projets. Faux manquant permanent.
#   - Productible mais non prescrit → dérive diagnostiquée par RD-17 : un dev qui
#     lit les conventions ignore une partie de l'arborescence documentaire.
#
# Autorité retenue : la capacité de PRODUCTION — sections « ## <fichier>.md » de
# references/stack-templates.md pour les documents techniques, une commande
# dédiée par document produit pour les documents produit. Volontairement PAS
# l'ordre d'affichage du générateur de mkdocs.yml : c'est un ordre permissif (il
# accepte n'importe quel .md via repli titlecase), pas une prescription — et ce
# générateur a quitté le plugin en RD-21, il vit désormais dans ezacae-ci-utils.
#
# Aucune dépendance externe. Compatible bash 3.2.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

CONV="$REPO_ROOT/plugins/ezacae-base/conventions.md"
TPL="$REPO_ROOT/plugins/ezacae-doc/references/stack-templates.md"
CMD_DIR="$REPO_ROOT/plugins/ezacae-doc/commands"

FAILS=0
pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1"; FAILS=$((FAILS + 1)); }

for f in "$CONV" "$TPL"; do
  [ -f "$f" ] || { echo "  FAIL — fichier introuvable : $f" >&2; exit 2; }
done
[ -d "$CMD_DIR" ] || { echo "  FAIL — dossier introuvable : $CMD_DIR" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/conventions-structure-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# --- Documents PRESCRITS : les *.md du bloc clôturé sous le titre Structure ----
prescribed() {
  awk '
    /^## Structure documentaire par projet/ { inblock=1; next }
    inblock && /^## /                       { exit }
    inblock && /^```/                       { fence = !fence; next }
    inblock && fence                        { print }
  ' "$1" | grep -oE '[A-Za-z0-9_-]+\.md' | LC_ALL=C sort -u
}

# --- Documents PRODUCTIBLES ---------------------------------------------------
# a) documents techniques : une section « ## <fichier>.md » dans
#    stack-templates.md (contrat lu par l'agent stack-writer)
# b) documents produit : une commande dédiée existe pour chacun
producible() {
  {
    grep -oE '^## [A-Za-z0-9_-]+\.md$' "$TPL" | sed 's/^## //'
    for pair in vision-produit.md:vision.md \
                personas-projet.md:personas.md \
                processus-projet.md:processus.md; do
      cmd="${pair%%:*}"; doc="${pair##*:}"
      [ -f "$CMD_DIR/$cmd" ] && printf '%s\n' "$doc"
    done
  } | LC_ALL=C sort -u
}

# --- Cœur du garde-fou --------------------------------------------------------
# Compare un fichier de conventions à l'ensemble productible.
# Sortie : 0 si l'invariant tient, 1 sinon. Diagnostics sur stdout.
check_conventions() {
  local conv="$1" rc=0 P Q orphans missing
  P="$(prescribed "$conv")"
  Q="$(producible)"

  if [ -z "$P" ]; then
    echo "    aucun document prescrit — section « Structure documentaire par projet » absente ou bloc non clôturé dans $conv"
    return 1
  fi

  orphans="$(comm -23 <(printf '%s\n' "$P") <(printf '%s\n' "$Q"))"
  missing="$(comm -13 <(printf '%s\n' "$P") <(printf '%s\n' "$Q"))"

  if [ -n "$orphans" ]; then
    echo "    prescrit dans conventions.md mais AUCUN outil ne le produit :"
    printf '      → %s\n' $orphans
    echo "    effet : /mike Phase 2 le signale « ⬜ Manquant » sur tous les projets, indéfiniment."
    rc=1
  fi
  if [ -n "$missing" ]; then
    echo "    productible par le plugin mais ABSENT de conventions.md :"
    printf '      → %s\n' $missing
    echo "    effet : un dev qui lit les conventions ignore cette partie de l'arborescence (dérive RD-17)."
    rc=1
  fi
  return "$rc"
}

# --- 1. Invariant sur l'état réel du dépôt ------------------------------------
echo "conventions.md ≡ documents productibles"
if out="$(check_conventions "$CONV")"; then
  pass "invariant tenu ($(prescribed "$CONV" | grep -c .) documents prescrits)"
else
  printf '%s\n' "$out"
  fail "invariant rompu — conventions.md et le plugin ne décrivent pas la même arborescence"
fi

# --- 2. Le garde-fou détecte un document productible non prescrit -------------
# (sans quoi un test toujours vert ne prouverait rien)
echo "détection des écarts"
FIX_MISSING="$WORK/conventions-missing.md"
{
  echo "## Structure documentaire par projet"
  echo '```'
  echo "docs/"
  echo "└── 00_vision/"
  echo "    └── vision.md"
  echo '```'
} > "$FIX_MISSING"
if check_conventions "$FIX_MISSING" >/dev/null; then
  fail "un fichier de conventions incomplet passe le contrôle (faux négatif)"
else
  pass "conventions incomplètes → détectées"
fi

# --- 3. Le garde-fou détecte un document prescrit non productible -------------
FIX_ORPHAN="$WORK/conventions-orphan.md"
{
  echo "## Structure documentaire par projet"
  echo '```'
  echo "docs/"
  prescribed "$CONV" | sed 's/^/    /'
  echo "    document-fantome.md"
  echo '```'
} > "$FIX_ORPHAN"
if check_conventions "$FIX_ORPHAN" >/dev/null; then
  fail "un document prescrit sans producteur passe le contrôle (faux négatif)"
else
  pass "document prescrit sans producteur → détecté"
fi

# --- Bilan --------------------------------------------------------------------
echo
if [ "$FAILS" -eq 0 ]; then
  echo "Tous les tests passent."
  exit 0
fi
echo "$FAILS test(s) en échec."
exit 1
