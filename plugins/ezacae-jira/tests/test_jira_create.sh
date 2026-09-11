#!/usr/bin/env bash
# Test PASS/FAIL de la création de ticket et du parcours /scope côté scripts (RD-44).
#
# Hors-ligne : faux Jira (fake-jira.py). Ce que /scope demande à nos scripts :
#   1. jira-create.sh crée l'épique : POST /rest/api/3/issue, le corps porte le
#      projet, le type demandé (nom), le résumé et les étiquettes ; la clé rendue
#      par Jira est affichée.
#   2. jira-edit.sh --label pose l'étiquette de taille (PUT, pas de POST).
#   3. jira-transition.sh passe en CONCEPTION VALIDATION (« à valider »).
#   4. jira-transition.sh refuse « Conception OK » : la porte reste humaine (RD-43),
#      aucun POST n'est envoyé.
#
# Lancer : bash plugins/ezacae-jira/tests/test_jira_create.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
FAUX_JIRA="${FAUX_JIRA:-$HERE/fake-jira.py}"
. "$HERE/harness.sh"

command -v python3 >/dev/null 2>&1 || { echo "⛔ python3 requis pour le faux Jira — test ignoré." >&2; exit 0; }

TMP=$(mktemp -d)
trap 'kill "${SRV_PID:-}" 2>/dev/null; wait "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

python3 "$FAUX_JIRA" > "$TMP/port" 2>"$TMP/srv.err" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT=$(cat "$TMP/port" 2>/dev/null)
[ -n "$PORT" ] || { echo "⛔ faux Jira non démarré : $(cat "$TMP/srv.err" 2>/dev/null)"; exit 1; }

export JIRA_BASE_URL="http://127.0.0.1:$PORT"
export JIRA_EMAIL="test@example.invalid"
export JIRA_API_TOKEN="jeton-secret-de-test"

post_count()    { curl -s "$JIRA_BASE_URL/post-count" | jq -r '.count'; }
created_issues(){ curl -s "$JIRA_BASE_URL/created-issues"; }

# === 1. jira-create.sh crée l'épique ==============================================
"$SCRIPTS/jira-create.sh" --project RD --type Epic --summary "Facturer des abonnements B2B" \
  --label harnais-test >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -eq 0 ] && ok "jira-create.sh rend 0" || nope "jira-create.sh échoue (rc=$RC) : $(tr -d '\n' <"$TMP/e")"
grep -qE 'RD-[0-9]+' "$TMP/o" && ok "la clé créée est affichée : $(grep -oE 'RD-[0-9]+' "$TMP/o" | head -1)" \
  || nope "clé absente de la sortie : $(cat "$TMP/o")"

created_issues >"$TMP/created.json"
[ "$(jq -r 'length' "$TMP/created.json" 2>/dev/null)" = "1" ] && ok "un seul POST /issue reçu" \
  || nope "POST /issue attendu une fois, reçu : $(cat "$TMP/created.json")"
body=$(jq -c '.[0].fields' "$TMP/created.json" 2>/dev/null)
[ "$(printf '%s' "$body" | jq -r '.project.key')" = "RD" ] && ok "corps : projet RD" || nope "corps : projet ≠ RD : $body"
[ "$(printf '%s' "$body" | jq -r '.issuetype.name')" = "Epic" ] && ok "corps : type Epic par son nom" || nope "corps : type ≠ Epic : $body"
[ "$(printf '%s' "$body" | jq -r '.summary')" = "Facturer des abonnements B2B" ] && ok "corps : résumé transmis" || nope "corps : résumé : $body"
[ "$(printf '%s' "$body" | jq -r '.labels[0]')" = "harnais-test" ] && ok "corps : étiquette transmise" || nope "corps : étiquettes : $body"

# === 2. L'étiquette de taille se pose sans transition ==============================
before=$(post_count)
"$SCRIPTS/jira-edit.sh" RD-WORKLOG --label taille-S >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -eq 0 ] && ok "jira-edit.sh --label taille-S rend 0" || nope "jira-edit.sh --label échoue (rc=$RC) : $(tr -d '\n' <"$TMP/e")"
[ "$(post_count)" = "$before" ] && ok "poser l'étiquette n'envoie aucune transition" || nope "poser l'étiquette a envoyé une transition"

# === 3. Passage en « à valider » ===================================================
before=$(post_count)
"$SCRIPTS/jira-transition.sh" RD-WORKLOG "CONCEPTION VALIDATION" --worklog 15m >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -eq 0 ] && [ "$(post_count)" = "$((before+1))" ] && ok "→ CONCEPTION VALIDATION passe (un POST)" \
  || nope "→ CONCEPTION VALIDATION échoue (rc=$RC) : $(tr -d '\n' <"$TMP/e")"

# === 4. La porte reste humaine =====================================================
before=$(post_count)
"$SCRIPTS/jira-transition.sh" RD-PORTE "Conception OK" >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -ne 0 ] && ok "→ Conception OK refusée (rc=$RC)" || nope "→ Conception OK ACCEPTÉE"
[ "$(post_count)" = "$before" ] && ok "refus : aucun POST envoyé" || nope "refus : un POST est parti"

test_summary
