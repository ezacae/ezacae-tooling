#!/usr/bin/env bash
# Test PASS/FAIL de la porte de validation refusée à l'assistant (RD-43).
#
# Spec brique 1, section 3 : « nos scripts Jira, seul chemin de l'assistant vers
# les tickets, refuseront cette transition ». La porte = la transition dont le
# statut cible est CONCEPTION OK (validation de la conception/spécification par
# un humain, qui clique lui-même dans Jira).
#
# Hors-ligne : faux Jira (fake-jira.py), ticket RD-PORTE en CONCEPTION VALIDATION
# avec deux transitions : 51 → « Conception OK » (porte) et 52 → CONCEPTION.
#
# Invariants :
#   1. jira-transition.sh refuse la porte : rc ≠ 0, message « validation humaine
#      dans Jira » sur stderr, AUCUN POST envoyé (compteur du faux Jira).
#   2. Insensible à la casse (« Conception OK », « conception ok », « CONCEPTION OK »).
#   3. La garde partagée (jira-lib.sh) refuse la porte quel que soit le statut
#      courant, y compris hors pipeline : la cible seule décide.
#   4. Le hook jira-guard.sh (voie MCP transitionJiraIssue) refuse aussi, avec
#      le même message.
#   5. Les autres transitions passent toujours : RD-PORTE → CONCEPTION (POST 52),
#      RD-WORKLOG → CONCEPTION VALIDATION --worklog (POST 31), annulation.
#
# Lancer : bash plugins/ezacae-jira/tests/test_jira_gate.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
GUARD="$HERE/../hooks/jira-guard.sh"
FAUX_JIRA="${FAUX_JIRA:-$HERE/fake-jira.py}"
. "$HERE/harness.sh"

command -v python3 >/dev/null 2>&1 || { echo "⛔ python3 requis pour le faux Jira — test ignoré." >&2; exit 0; }

TMP=$(mktemp -d)
trap 'kill "${SRV_PID:-}" 2>/dev/null; rm -rf "$TMP"' EXIT

python3 "$FAUX_JIRA" > "$TMP/port" 2>"$TMP/srv.err" &
SRV_PID=$!
for _ in $(seq 1 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT=$(cat "$TMP/port" 2>/dev/null)
[ -n "$PORT" ] || { echo "⛔ faux Jira non démarré : $(cat "$TMP/srv.err" 2>/dev/null)"; exit 1; }

export JIRA_BASE_URL="http://127.0.0.1:$PORT"
export JIRA_EMAIL="test@example.invalid"
export JIRA_API_TOKEN="jeton-secret-de-test"
# shellcheck disable=SC1090
. "$SCRIPTS/jira-lib.sh"

post_count() { curl -s "$JIRA_BASE_URL/post-count" | jq -r '.count'; }
MSG="validation humaine dans Jira"

# === 1-2. jira-transition.sh refuse la porte, sans POST, quelle que soit la casse ==
for cible in "Conception OK" "conception ok" "CONCEPTION OK"; do
  before=$(post_count)
  "$SCRIPTS/jira-transition.sh" RD-PORTE "$cible" >"$TMP/o" 2>"$TMP/e"; RC=$?
  [ "$RC" -ne 0 ] && ok "porte « $cible » refusée par jira-transition.sh (rc=$RC)" \
    || nope "porte « $cible » ACCEPTÉE par jira-transition.sh (rc=0)"
  grep -qF "$MSG" "$TMP/e" && ok "porte « $cible » : le message dit quoi faire ($MSG)" \
    || nope "porte « $cible » : message absent de stderr : $(tr -d '\n' <"$TMP/e")"
  [ "$(post_count)" = "$before" ] && ok "porte « $cible » : aucun POST envoyé au Jira" \
    || nope "porte « $cible » : un POST est parti vers Jira malgré le refus"
done

# === 3. La garde partagée refuse la porte depuis n'importe quel statut =============
for cur in "CONCEPTION VALIDATION" "Nouveau" "Terminé(e)" "En cours"; do
  if jira_pipeline_guard "$cur" "CONCEPTION OK" >"$TMP/g" 2>&1; then
    nope "garde : '$cur' → CONCEPTION OK autorisée (devrait être refusée)"
  else
    grep -qF "$MSG" "$TMP/g" && ok "garde : '$cur' → CONCEPTION OK refusée avec le bon message" \
      || nope "garde : '$cur' → CONCEPTION OK refusée mais message inattendu : $(cat "$TMP/g")"
  fi
done
jira_pipeline_guard "CONCEPTION VALIDATION" "CONCEPTION" >/dev/null 2>&1 \
  && ok "garde : CONCEPTION VALIDATION → CONCEPTION reste autorisée" \
  || nope "garde : CONCEPTION VALIDATION → CONCEPTION refusée à tort"
jira_pipeline_guard "CADRAGE" "CONCEPTION" >/dev/null 2>&1 \
  && ok "garde : CADRAGE → CONCEPTION reste autorisée" || nope "garde : CADRAGE → CONCEPTION refusée à tort"
jira_pipeline_guard "CONCEPTION OK" "EN COURS" >/dev/null 2>&1 \
  && ok "garde : CONCEPTION OK → EN COURS reste autorisée (après le clic humain)" \
  || nope "garde : CONCEPTION OK → EN COURS refusée à tort"
jira_pipeline_guard "CONCEPTION VALIDATION" "Annulé" >/dev/null 2>&1 \
  && ok "garde : annulation toujours autorisée" || nope "garde : annulation refusée à tort"

# === 4. Le hook jira-guard.sh (voie MCP) refuse la porte ===========================
input=$(jq -n '{tool_name:"mcp__claude_ai_Atlassian__transitionJiraIssue", tool_input:{issueIdOrKey:"RD-PORTE", transitionId:"51"}}')
dec=$(bash "$GUARD" <<<"$input")
[ "$(printf '%s' "$dec" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ] \
  && ok "hook jira-guard.sh : transition 51 (porte) → deny" \
  || nope "hook jira-guard.sh : transition 51 (porte) non refusée : $dec"
printf '%s' "$dec" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' | grep -qF "$MSG" \
  && ok "hook jira-guard.sh : motif = $MSG" || nope "hook jira-guard.sh : motif inattendu : $dec"
input=$(jq -n '{tool_name:"mcp__claude_ai_Atlassian__transitionJiraIssue", tool_input:{issueIdOrKey:"RD-PORTE", transitionId:"52"}}')
[ "$(bash "$GUARD" <<<"$input" | jq -r '.hookSpecificOutput.permissionDecision')" = "allow" ] \
  && ok "hook jira-guard.sh : transition 52 (retour CONCEPTION) → allow" \
  || nope "hook jira-guard.sh : transition 52 refusée à tort"

# === 5. Les autres transitions passent toujours ====================================
before=$(post_count)
"$SCRIPTS/jira-transition.sh" RD-PORTE CONCEPTION >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -eq 0 ] && [ "$(post_count)" = "$((before+1))" ] \
  && ok "RD-PORTE → CONCEPTION passe (rc=0, un POST)" \
  || nope "RD-PORTE → CONCEPTION échoue (rc=$RC) : $(tr -d '\n' <"$TMP/e")"
before=$(post_count)
"$SCRIPTS/jira-transition.sh" RD-WORKLOG "CONCEPTION VALIDATION" --worklog 30m >"$TMP/o" 2>"$TMP/e"; RC=$?
[ "$RC" -eq 0 ] && [ "$(post_count)" = "$((before+1))" ] \
  && ok "RD-WORKLOG → CONCEPTION VALIDATION --worklog passe (rc=0, un POST)" \
  || nope "RD-WORKLOG → CONCEPTION VALIDATION échoue (rc=$RC) : $(tr -d '\n' <"$TMP/e")"

test_summary
