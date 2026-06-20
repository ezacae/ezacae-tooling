# jira-watcher — déclencheur /mike automatique

Watcher Python packagé en image Claude Code headless. Toutes les 15 minutes, il
interroge JIRA (REST v3) sur une liste de projets configurée dans une ConfigMap,
sélectionne les tickets au statut `NOUVEAU` portant l'étiquette `claude` et non encore
`claude-traite`, pose le label de claim `claude-traite`, puis lance `/mike <clé>` en
mode headless (cycle complet : cadrage → `CONCEPTION` → `/sarah`).

---

## 1. Configuration (ConfigMap)

La ConfigMap `jira-watcher-config` est montée en `/etc/jira-watcher/config.yaml`.

| Champ | Type | Description |
|---|---|---|
| `jira_base_url` | string | URL de base JIRA Cloud (ex. `https://ezacae.atlassian.net`) |
| `projects` | list[str] | Clés de projets surveillés (ex. `["CRM", "ACME"]`) |
| `trigger_label` | string | Étiquette d'éligibilité (défaut : `claude`) |
| `claim_label` | string | Étiquette de déduplication (défaut : `claude-traite`) |
| `watched_statuses` | list[str] | Statuts déclencheurs (ex. `["NOUVEAU"]`) |
| `slash_command` | string | Commande lancée — `{key}` est remplacé par la clé ticket |
| `claude_timeout_seconds` | int | Timeout par run `/mike` en secondes (défaut : 3600) |
| `max_issues_per_run` | int | Plafond de tickets traités par cycle (défaut : 10) |

Modifier `k8s/configmap.yaml` pour ajuster les projets ou le plafond, puis redéployer.

---

## 2. Credentials (Secret)

Le Secret `jira-watcher-secrets` (à créer hors Git — voir gabarit `k8s/secret.example.yaml`)
doit contenir :

| Clé | Usage |
|---|---|
| `jira-email` | Auth Basic REST JIRA (email du compte API) |
| `jira-api-token` | Auth Basic REST JIRA (token API Atlassian) |
| `claude-credentials.json` | OAuth Claude CLI + OAuth MCP Atlassian distant |

---

## 3. Capture et renouvellement des credentials

Les credentials OAuth (`claude-credentials.json`) sont stockés dans
`~/.claude/.credentials.json` après authentification interactive.

### Capture initiale (ou renouvellement)

1. Sur un poste authentifié (abonnement Claude actif) :

   ```bash
   claude   # connexion interactive si nécessaire
   # Vérifier que le MCP Atlassian est autorisé en lançant une commande qui l'utilise,
   # par exemple : /mike DEMO-1 (nécessite un ticket DEMO-1 accessible)
   ```

2. Copier les credentials :

   ```bash
   cp ~/.claude/.credentials.json /tmp/claude-credentials.json
   ```

3. Créer ou mettre à jour le Secret Kubernetes :

   ```bash
   kubectl create secret generic jira-watcher-secrets \
     --namespace jira-watcher \
     --from-literal=jira-email=votre@email.com \
     --from-literal=jira-api-token=VOTRE_TOKEN_JIRA \
     --from-file=claude-credentials.json=/tmp/claude-credentials.json \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. Supprimer le fichier temporaire :

   ```bash
   rm /tmp/claude-credentials.json
   ```

### Indicateur d'expiration

Quand les credentials expirent, le watcher retourne un code de sortie ≠ 0 avec un log
explicite `Erreur d'infrastructure`. ArgoCD / votre système d'alerte doit surveiller les
jobs en échec dans le namespace `jira-watcher`.

---

## 4. Reprise manuelle d'un ticket en échec

Si `/mike` échoue sur un ticket, le label `claude-traite` est conservé intentionnellement
(pas de relance automatique = pas de thrash).

Pour relancer le traitement d'un ticket :

```bash
# Retirer le label de claim via l'API JIRA REST
# (ou via l'interface JIRA : étiquettes du ticket → retirer "claude-traite")
curl -u "$JIRA_EMAIL:$JIRA_API_TOKEN" \
  -X PUT \
  -H "Content-Type: application/json" \
  -d '{"update":{"labels":[{"remove":"claude-traite"}]}}' \
  "https://ezacae.atlassian.net/rest/api/3/issue/CRM-42"
```

Le ticket sera repris au prochain cycle du watcher.

---

## 5. Déploiement ArgoCD

L'application ArgoCD est définie dans `k8s/application.yaml`. Elle surveille le
répertoire `deploy/jira-watcher/k8s` de ce dépôt.

### Premier déploiement

```bash
# Créer le namespace et le secret d'abord (voir §3)
kubectl create namespace jira-watcher

# Appliquer l'Application ArgoCD (nécessite le CRD ArgoCD)
kubectl apply -f deploy/jira-watcher/k8s/application.yaml

# ArgoCD synchronise automatiquement les autres ressources
```

### Validation des manifestes (sans cluster)

```bash
kubectl apply --dry-run=client -k deploy/jira-watcher/k8s
# ou
kustomize build deploy/jira-watcher/k8s | kubectl apply --dry-run=client -f -
```

---

## 6. Build et test local

```bash
# Installation des dépendances de développement
pip install -e "deploy/jira-watcher[dev]"

# Lancer les tests
pytest deploy/jira-watcher/tests -v

# Mode dry-run (nécessite JIRA_EMAIL, JIRA_API_TOKEN et config.yaml)
JIRA_EMAIL=you@company.com JIRA_API_TOKEN=xxx \
  python -m jira_watcher --config /etc/jira-watcher/config.yaml --dry-run

# Build de l'image (depuis la racine du repo)
docker build \
  -f deploy/jira-watcher/Dockerfile \
  -t jira-watcher:local \
  .
```
