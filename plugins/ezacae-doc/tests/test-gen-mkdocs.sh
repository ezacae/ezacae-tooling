#!/usr/bin/env bash
#
# test-gen-mkdocs.sh — tests du générateur mkdocs.yml (RD-2).
#
# Golden-file + propriétés : présence garantie, ordre déterministe, synchro
# création/suppression, idempotence, garde absence de docs/.
# Aucune dépendance externe. Compatible bash 3.2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/../scripts/gen-mkdocs.sh"

FAILS=0
pass() { echo "  ok   — $1"; }
fail() { echo "  FAIL — $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gen-mkdocs-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkfile() { mkdir -p "$(dirname "$1")"; : > "$1"; }

# --- Fixture -------------------------------------------------------------------
REPO="$WORK/repo"
build_fixture() {
  rm -rf "$REPO"; mkdir -p "$REPO"
  mkfile "$REPO/docs/index.md"
  mkfile "$REPO/docs/glossaire.md"
  mkfile "$REPO/docs/00_vision/vision.md"
  mkfile "$REPO/docs/01_product/personas.md"
  mkfile "$REPO/docs/01_product/processus.md"
  mkfile "$REPO/docs/01_product/roadmap.md"
  mkfile "$REPO/docs/02_architecture/auth.md"
  mkfile "$REPO/docs/02_architecture/deep/thing.md"
  mkfile "$REPO/docs/03_donnees/bdd.md"
  mkfile "$REPO/docs/03_donnees/api-endpoints.md"
  mkfile "$REPO/docs/99_annexes/faq.md"
}

read -r -d '' GOLDEN <<'EOF' || true
site_name: "Documentation — Projet Test"
docs_dir: docs
theme:
  name: material
nav:
  - Accueil: index.md
  - Glossaire: glossaire.md
  - Vision:
      - Vision produit: 00_vision/vision.md
  - Produit:
      - Personas: 01_product/personas.md
      - Processus métier: 01_product/processus.md
      - Roadmap: 01_product/roadmap.md
  - Architecture:
      - Authentification: 02_architecture/auth.md
      - Thing: 02_architecture/deep/thing.md
  - Données:
      - Modèle de données: 03_donnees/bdd.md
      - API endpoints: 03_donnees/api-endpoints.md
  - 99 annexes:
      - Faq: 99_annexes/faq.md
EOF

echo "Test 1 — golden-file (arbre complet, ordre, labels, sections inconnues, deep)"
build_fixture
[ ! -f "$REPO/mkdocs.yml" ] || fail "mkdocs.yml présent avant génération"
bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" >/dev/null
if [ -f "$REPO/mkdocs.yml" ]; then pass "mkdocs.yml créé quand absent"
else fail "mkdocs.yml non créé"; fi
if diff -u <(printf '%s\n' "$GOLDEN") "$REPO/mkdocs.yml"; then
  pass "sortie == golden"
else
  fail "sortie != golden (voir diff ci-dessus)"
fi

echo "Test 2 — idempotence (2e run identique)"
FIRST="$(cat "$REPO/mkdocs.yml")"
bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" >/dev/null
if [ "$FIRST" = "$(cat "$REPO/mkdocs.yml")" ]; then pass "run 2 identique au run 1"
else fail "sortie non idempotente"; fi

echo "Test 3 — suppression d'un .md reflétée après régénération"
rm "$REPO/docs/01_product/roadmap.md"
bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" >/dev/null
if grep -q "roadmap.md" "$REPO/mkdocs.yml"; then fail "roadmap.md encore dans nav après suppression"
else pass "entrée supprimée du nav"; fi

echo "Test 4 — création d'un .md reflétée après régénération"
mkfile "$REPO/docs/01_product/fonctions.md"
bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" >/dev/null
if grep -q "Fonctionnalités: 01_product/fonctions.md" "$REPO/mkdocs.yml"; then pass "nouvelle entrée présente avec le bon label"
else fail "fonctions.md absent du nav ou mauvais label"; fi

echo "Test 5 — site_name extrait de .claude/CLAUDE.md (H1)"
REPO2="$WORK/repo2"; mkdir -p "$REPO2/docs/00_vision" "$REPO2/.claude"
: > "$REPO2/docs/00_vision/vision.md"
printf '# Mon Super Projet\n\nblabla\n' > "$REPO2/.claude/CLAUDE.md"
bash "$GEN" "$REPO2" >/dev/null
if head -1 "$REPO2/mkdocs.yml" | grep -qx 'site_name: "Documentation — Mon Super Projet"'; then
  pass "site_name dérivé du H1 de CLAUDE.md"
else fail "site_name mal résolu : $(head -1 "$REPO2/mkdocs.yml")"; fi

echo "Test 6 — garde : pas de docs/ → exit non nul, aucun mkdocs.yml"
REPO3="$WORK/repo3"; mkdir -p "$REPO3"
if bash "$GEN" "$REPO3" >/dev/null 2>&1; then fail "devrait échouer sans docs/"
else pass "échec propre sans docs/"; fi
[ ! -f "$REPO3/mkdocs.yml" ] || fail "mkdocs.yml écrit alors que docs/ absent"

echo "Test 7 — garde : docs/ vide (aucun .md) → exit non nul"
REPO4="$WORK/repo4"; mkdir -p "$REPO4/docs"
if bash "$GEN" "$REPO4" >/dev/null 2>&1; then fail "devrait échouer si docs/ sans .md"
else pass "échec propre si docs/ sans .md"; fi

echo "Test 8 — site_name échappé (H1 avec guillemets et esperluette)"
REPO5="$WORK/repo5"; mkdir -p "$REPO5/docs/00_vision" "$REPO5/.claude"
: > "$REPO5/docs/00_vision/vision.md"
printf '# Projet "Alpha" & Co\n' > "$REPO5/.claude/CLAUDE.md"
bash "$GEN" "$REPO5" >/dev/null
if head -1 "$REPO5/mkdocs.yml" | grep -qx 'site_name: "Documentation — Projet \\"Alpha\\" & Co"'; then
  pass "guillemets échappés dans site_name"
else fail "échappement YAML incorrect : $(head -1 "$REPO5/mkdocs.yml")"; fi

echo "Test 9 — --check : sort 0 si à jour"
build_fixture
bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" >/dev/null
if bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" --check >/dev/null 2>&1; then
  pass "--check == 0 quand à jour"
else fail "--check devrait sortir 0 quand à jour"; fi

echo "Test 10 — --check : sort non nul si périmé, sans réécrire le fichier"
mkfile "$REPO/docs/03_donnees/nouveau.md"
BEFORE="$(cat "$REPO/mkdocs.yml")"
if bash "$GEN" "$REPO" --site-name "Documentation — Projet Test" --check >/dev/null 2>&1; then
  fail "--check devrait sortir non nul quand périmé"
else pass "--check != 0 quand périmé"; fi
if [ "$BEFORE" = "$(cat "$REPO/mkdocs.yml")" ]; then pass "--check n'a pas modifié mkdocs.yml"
else fail "--check a écrit le fichier (ne devrait jamais)"; fi

echo "Test 11 — --check : sort non nul si mkdocs.yml absent"
REPO6="$WORK/repo6"; mkdir -p "$REPO6/docs/00_vision"; : > "$REPO6/docs/00_vision/vision.md"
if bash "$GEN" "$REPO6" --check >/dev/null 2>&1; then fail "--check devrait sortir non nul si absent"
else pass "--check != 0 quand mkdocs.yml absent"; fi
[ ! -f "$REPO6/mkdocs.yml" ] || fail "--check a créé mkdocs.yml (ne devrait jamais)"

echo ""
if [ "$FAILS" -eq 0 ]; then echo "TOUS LES TESTS PASSENT ✅"; exit 0
else echo "$FAILS test(s) en échec ❌"; exit 1; fi
