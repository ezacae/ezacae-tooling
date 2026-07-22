#!/usr/bin/env bash
# Test PASS/FAIL du hook jira-guard.sh — redirection MCP → helpers REST (RD-15).
#
# 100% hors-ligne : chaque cas est décidé par le hook AVANT tout appel réseau
# (une redirection/allow sort avant que jira_status ne soit invoqué). Ne requiert
# que `jq` + bash. Lancer : bash plugins/ezacae-jira/tests/test_jira_guard.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../hooks/jira-guard.sh"
PASS=0; FAIL=0
A="mcp__claude_ai_Atlassian__"

# run_guard <tool_name> <issueKey> <present|absent> → JSON de décision sur stdout.
# 'absent' pointe CLAUDE_PROJECT_DIR vers un dossier sans .claude/jira.env pour
# garantir qu'aucun credential n'est chargé, quel que soit le cwd du testeur.
run_guard() {
  local tool="$1" key="$2" creds="$3" input
  input=$(jq -n --arg t "$tool" --arg k "$key" '{tool_name:$t, tool_input:{issueIdOrKey:$k}}')
  if [ "$creds" = present ]; then
    JIRA_BASE_URL="https://ezacae.atlassian.net" JIRA_EMAIL="t@e.com" JIRA_API_TOKEN="x" \
      bash "$GUARD" <<<"$input"
  else
    env -u JIRA_BASE_URL -u JIRA_EMAIL -u JIRA_API_TOKEN CLAUDE_PROJECT_DIR=/nonexistent \
      bash "$GUARD" <<<"$input"
  fi
}

# check <label> <json> <décision attendue> [sous-chaîne attendue dans le motif]
check() {
  local label="$1" json="$2" exp="$3" sub="${4:-}" dec reason
  dec=$(printf '%s' "$json" | jq -r '.hookSpecificOutput.permissionDecision // empty')
  reason=$(printf '%s' "$json" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
  if [ "$dec" != "$exp" ]; then
    echo "FAIL  $label — décision attendue '$exp', obtenue '$dec'"; FAIL=$((FAIL+1)); return
  fi
  if [ -n "$sub" ] && [[ "$reason" != *"$sub"* ]]; then
    echo "FAIL  $label — motif sans '$sub' : $reason"; FAIL=$((FAIL+1)); return
  fi
  echo "PASS  $label"; PASS=$((PASS+1))
}

# --- Opérations AVEC helper : le MCP doit être redirigé (deny + nom du helper) ---
check "getJiraIssue + creds → deny vers jira-get.sh" \
  "$(run_guard "${A}getJiraIssue" RD-15 present)" deny "jira-get.sh"
check "addComment + creds → deny vers jira-comment.sh" \
  "$(run_guard "${A}addCommentToJiraIssue" RD-15 present)" deny "jira-comment.sh"
check "editJiraIssue + creds → deny vers jira-edit.sh" \
  "$(run_guard "${A}editJiraIssue" RD-15 present)" deny "jira-edit.sh"

# --- Credentials absents : bloquer + GUIDER pas à pas (pas de dégradation silencieuse) ---
absent_json="$(run_guard "${A}getJiraIssue" RD-15 absent)"
check "getJiraIssue sans creds → deny + instruit jira.env" "$absent_json" deny "jira.env"
check "getJiraIssue sans creds → guide : lien token API" "$absent_json" deny "api-tokens"
check "getJiraIssue sans creds → guide : commande cp du modèle" "$absent_json" deny "cp "

# --- transitionJiraIssue : comportement inchangé (garde, non redirigé) ------------
check "transition sans creds → allow (garde inactive, pas de redirection)" \
  "$(run_guard "${A}transitionJiraIssue" RD-15 absent)" allow

# --- Opérations AVEC helper ajouté (zéro-MCP) : redirigées elles aussi ------------
check "createJiraIssue + creds → deny vers jira-create.sh" \
  "$(run_guard "${A}createJiraIssue" "" present)" deny "jira-create.sh"
check "searchJiraIssuesUsingJql + creds → deny vers jira-search.sh" \
  "$(run_guard "${A}searchJiraIssuesUsingJql" "" present)" deny "jira-search.sh"
check "createIssueLink + creds → deny vers jira-link.sh" \
  "$(run_guard "${A}createIssueLink" "" present)" deny "jira-link.sh"
check "getVisibleJiraProjects + creds → deny vers jira-projects.sh" \
  "$(run_guard "${A}getVisibleJiraProjects" "" present)" deny "jira-projects.sh"
check "getJiraProjectIssueTypesMetadata + creds → deny vers jira-projects.sh" \
  "$(run_guard "${A}getJiraProjectIssueTypesMetadata" "" present)" deny "jira-projects.sh"

# --- Op MCP SANS helper : reste autorisée -----------------------------------------
check "getTransitionsForJiraIssue + creds → allow (pas de helper)" \
  "$(run_guard "${A}getTransitionsForJiraIssue" RD-15 present)" allow
check "addWorklogToJiraIssue + creds → allow (pas de helper)" \
  "$(run_guard "${A}addWorklogToJiraIssue" RD-15 present)" allow

echo "----"
echo "Résultat : PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
