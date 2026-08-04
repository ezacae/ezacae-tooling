# Remontée des erreurs Jira dans les helpers (RD-29)

Statut : Actif — conception technique, prête pour l'exécution.
Type : **bug**. Cadrage fonctionnel : `docs/conception/cadrage-rd-29-erreurs-helpers-jira.md`.

## Cause racine

`jira_curl` (`plugins/ezacae-jira/scripts/jira-lib.sh:35`) appelle `curl --fail`. Sur une réponse non-2xx, `--fail` **jette le corps** avant qu'il n'atteigne quoi que ce soit. Tous les appels réseau des onze helpers passent par cette fonction, donc tous perdent la même information.

Reproduit, mesuré, quatre familles :

| Appel | Sortie du helper | Corps réellement renvoyé par Jira |
|---|---|---|
| `GET /search/jql` (JQL invalide) | `curl: (56) … error: 400` | `errorMessages: ["Erreur dans la requête JQL : … (ligne 1, caractère 10)"]` |
| `GET /issue/RD-99999` | `curl: (56) … error: 404` | `errorMessages: ["Le ticket n'existe pas ou vous n'êtes pas autorisé à la voir."]` |
| `POST /transitions` (id invalide) | `curl: (56) … error: 400` | `errorMessages: ["Transition id '999999' is not valid for this issue."]` |
| `PUT /issue` (assignee = nom) | `curl: (56) … error: 400` | `errorMessages: []`, `errors: {"assignee": "Spécifiez une valeur valide pour assignee"}` |

Deux preuves que le défaut est bien dans la fonction commune et pas dans les appelants :

1. **`jira-create.sh:54` contient déjà le message soigné** — `⛔ Création échouée : $RESP` — et il est inatteignable : `set -e` tue le script à la ligne précédente, et `RESP` serait vide de toute façon. Vérifié avec un type de ticket inexistant : la sortie est `curl: (56) … error: 400`. L'intention d'origine était d'afficher la réponse ; `--fail` l'a rendue impossible.
2. **Le champ porteur du message change selon l'erreur.** L'échec d'assignation laisse `errorMessages` vide et met tout dans `errors`. Un correctif qui ne lirait qu'`errorMessages` laisserait muet le cas qui a coûté du temps sur RD-21.

### Ce que le code de sortie ne prouve pas

`--fail` produit **56** contre Atlassian en HTTPS (curl coupe la connexion, `CURLE_RECV_ERROR`) et **22** contre un serveur HTTP local. Le numéro dépend du transport, pas de nous : **aucun test ne doit l'asserter**. L'invariant testable est la présence du message sur stderr. Aucun script du dépôt ne teste cette valeur (vérifié) — elle est donc libre, à condition de rester non nulle.

## Décisions de conception

Trois forks tranchés avant écriture, chacun avec sa raison.

| Décision | Choix | Raison |
|---|---|---|
| Récupération du corps | **Deux fonctions** : corps en mémoire pour le JSON, fichier temporaire seulement pour les téléchargements | Aucun fichier temporaire sur le chemin du hook ; le binaire ne passe jamais par une variable shell (un octet nul la tronquerait) |
| Périmètre | **Une seule MR** : cœur + indice `--worklog` + résolution d'assigné + déduplication des pièces jointes | Quatre changements petits et indépendamment testables, un seul passage de revue |
| `--assignee <nom>` | **Résoudre si une seule correspondance**, refuser en listant sinon | Un homonyme ne doit pas produire une assignation silencieusement fausse ; mesuré : une requête vide renvoie 10 utilisateurs |

## Contraintes de plateforme

1. **Bash 3.2.** Le poste de dev tourne sur `/bin/bash` 3.2.57 (macOS) ; l'image du watcher est en bash 5 (Debian bookworm). Cible : **3.2**. Donc **pas de `declare -A`**, pas de `${var^^}`, pas de `mapfile`. Vérifié : `declare -A` échoue sur le poste.
2. **curl 7.88 (Debian) et 8.7.1 (macOS).** `--write-out '%{http_code}'` existe dans les deux depuis toujours. `--fail-with-body` existe aussi, mais n'est pas retenu (cf. cadrage : il écrit le corps d'erreur dans le fichier de destination).
3. **stdout appartient au parseur.** `jira-lib.sh` est sourcé par `jira-guard.sh`, qui capture `jira_status` par substitution de commande et jette stderr (`jira-guard.sh:105`). Un message sur stdout ne casse pas le JSON du hook — il vide la variable de statut, et la ligne 106 applique `allow`. La garde **s'ouvre en silence**. Le message part donc sur stderr, sans exception.
4. **Un seul appelant à remplacer.** `jira_transition_id_for_status` n'est utilisé qu'en `jira-transition.sh:42` (vérifié) : on peut le remplacer sans casser personne. `jira_status` est utilisé par le hook et par `jira-transition.sh` : son contrat ne change pas.

## Architecture

Tout le changement de comportement vit dans `jira-lib.sh`. Les appelants ne changent que là où le contrat évolue.

| Fichier | Nature du changement |
|---|---|
| `plugins/ezacae-jira/scripts/jira-lib.sh` | `jira_curl` réécrit ; ajout de `jira_report_http_error`, `jira_curl_to_file`, `jira_transitions`, `jira_looks_like_account_id`, `jira_resolve_assignee` ; `jira_transition_id_for_status` supprimé (remplacé) |
| `plugins/ezacae-jira/scripts/jira-download.sh` | passe à `jira_curl_to_file` ; déduplication des noms homonymes ; compteur honnête |
| `plugins/ezacae-jira/scripts/jira-transition.sh` | un seul appel aux transitions (avec `expand`), pré-contrôle des champs requis, indice `--worklog` |
| `plugins/ezacae-jira/scripts/jira-edit.sh` | `--assignee` accepte un nom d'affichage |
| `plugins/ezacae-jira/tests/test_jira_curl_errors.sh` | suite étendue (amorce déjà livrée avec le cadrage) |
| `plugins/ezacae-jira/tests/fake-jira.py` | faux Jira étendu (routes d'erreur, homonymes, 204, corps non-JSON) |

**Non touchés, volontairement** : `jira-get.sh` (RD-23 le modifie — on reste indépendant de l'ordre de fusion), `jira-guard.sh`, et les neuf autres helpers, qui héritent du correctif sans une ligne de changement.

### Contrat des fonctions

**`jira_curl <args curl…>`** — pour toute réponse JSON.

- 2xx → le corps sur **stdout**, octet pour octet, code de retour 0.
- non-2xx → **rien sur stdout**, message sur **stderr**, code de retour non nul.
- échec transport (timeout, DNS, TLS) → curl a déjà parlé sur stderr via `--show-error`, code non nul.

```bash
jira_curl() {
  local out code body
  out=$(curl --silent --show-error --write-out '\n%{http_code}' \
          --max-time "${JIRA_CURL_MAX_TIME:-20}" \
          -u "$JIRA_EMAIL:$JIRA_API_TOKEN" "$@") || return 1
  code=${out##*$'\n'}
  body=${out%$'\n'*}
  case "$code" in 2*) printf '%s' "$body"; return 0 ;; esac
  jira_report_http_error "$code" "$body"
  return 1
}
```

Points de vigilance, à couvrir par les tests :

- `--fail` **disparaît** : sans lui, curl sort en 0 sur un 4xx, et c'est `%{http_code}` qui décide. C'est le cœur du correctif.
- **`jira_curl` refuse `-o`/`--output` dans ses arguments** (une ligne, avant l'appel). Le contrat « rien sur stdout en cas d'échec » ne protège pas un fichier de sortie : un futur appelant qui passerait `-o` recevrait le corps d'erreur dans son fichier — exactement la corruption que `jira_curl_to_file` existe pour empêcher. La garde rend le mauvais usage impossible au lieu de l'espérer absent.
- La substitution de commande retire les sauts de ligne **de fin de capture** ; comme la capture finit par le code HTTP, les sauts de ligne internes au corps sont intacts. `printf '%s'` n'en rajoute pas.
- Réponse vide (`204 No Content`, cas des transitions) : la capture vaut `"\n204"`, donc `body` vide et `code=204`. Le contrat tient.

**`jira_curl_to_file <destination> <args curl…>`** — pour un contenu binaire ou volumineux.

- Écrit dans `<destination>.part.XXXXXX` (même dossier, donc même système de fichiers).
- 2xx → `mv` vers la destination. C'est la seule façon d'y créer un fichier.
- non-2xx ou échec transport → temporaire supprimé, **aucun fichier à destination**, message sur stderr, code non nul.
- Le corps d'erreur est tronqué à 2 000 octets avant affichage (une page HTML de proxy ne doit pas noyer le terminal).
- Un `trap` local nettoie le temporaire sur interruption (SIGINT/SIGTERM). Un SIGKILL peut laisser un `.part.*` orphelin — assumé et documenté dans l'en-tête de la fonction ; le test « aucun `.part.*` restant » porte sur les chemins d'échec normaux, pas sur kill -9.

**`jira_report_http_error <code> <corps>`** — le seul endroit qui écrit un message d'erreur.

- Écrit **sur stderr**, jamais stdout.
- Extrait `errorMessages` **et** `errors` (`clé : valeur`), les deux, via `jq`.
- Corps vide ou non-JSON → replie sur le code HTTP et les 200 premiers caractères du corps, sur une ligne.
- Silencieux si `JIRA_QUIET_ERRORS=1` — pour les appelants qui s'attendent à un échec (sondes, recherches optionnelles). Le hook n'en a pas besoin : il jette déjà stderr.
- **Itère les messages ligne par ligne** (`while IFS= read -r`). Un `printf '  • %s\n' $msgs` non quoté découperait les messages de Jira sur les espaces — ils sont en français, ils en contiennent.
- N'affiche **jamais** la commande, les en-têtes, ni l'URL complète avec identifiants : le jeton est passé en `-u` sur la ligne de commande de curl.

Format retenu, court parce que la sortie d'un hook part en contexte d'agent :

```
⛔ Jira a refusé la requête (HTTP 400)
   • Le temps consacré est obligatoire
   → ajoute --worklog <durée> (ex. 30m)
```

La flèche n'apparaît que si un appelant a une suggestion à faire ; `jira_report_http_error` ne l'invente pas.

### Les trois retombées

**1. Indice `--worklog` — sans dépendre de la langue.** Jira répond dans la langue du compte : « Le temps consacré est obligatoire » devient « Time spent is required » pour un profil en anglais. On ne lit donc pas le message, on lit les **champs requis**, par leur nom technique.

`jira_transitions <KEY>` remplace `jira_transition_id_for_status` et renvoie le JSON de `GET /rest/api/3/issue/<KEY>/transitions?expand=transitions.fields`. `jira-transition.sh` en tire, **sur le même appel qu'aujourd'hui** (pas une requête de plus), l'id de la transition et la liste de ses champs requis. Mesuré sur RD-29 :

```
Conception terminée → CONCEPTION VALIDATION | ecran=true | requis: worklog
Annulé              → Annulé                | ecran=true | requis: worklog,resolution
```

**Le pré-vol ne refuse que ce qui est mesuré fatal : `worklog`.** Si `worklog` est requis et `--worklog` absent, refuser avant d'envoyer en citant l'option — c'est le cas d'origine du ticket, dont l'échec est prouvé. Pour **tout autre champ requis** (`resolution`, champ custom…), **tenter le POST quand même** et laisser la nouvelle remontée d'erreur parler : les écrans Jira portent souvent une valeur par défaut, et un refus côté client fermerait des transitions que le serveur accepte. Le cas concret est l'annulation — `Annulé` exige `worklog,resolution` (mesuré), la garde de statut l'autorise **toujours** (`jira-lib.sh:94-96`, c'est la soupape du pipeline), et refuser en pré-vol sur `resolution` la rendrait impossible via le helper alors qu'une résolution par défaut peut suffire côté serveur. Règle générale : **pré-vol seulement sur ce qui est mesuré fatal ; tentative pour ce qu'on ne sait pas.**

**La comparaison de statut reste dans jq, jamais en shell.** `jira_transition_id_for_status` disparaît, mais son commentaire (`jira-lib.sh:49-52`) protège un piège qui survit au remplacement : un `tr '[:lower:]' '[:upper:]'` shell dépend de la locale et rate `é`→`É`, d'où un faux négatif sur « Annulé ». L'extraction de l'id depuis le JSON de `jira_transitions` fait donc sa correspondance **entièrement dans jq** (`ascii_upcase` des deux côtés), et le faux Jira des tests expose **au moins un statut accentué** (`Annulé`) pour que la régression soit détectable — les statuts ASCII ne la révèlent pas.

**2. `--assignee` accepte un nom d'affichage.** `jira_looks_like_account_id` reconnaît un identifiant (24 caractères hexadécimaux — mesuré : `6256cf820630bd0070761e65` — ou une forme contenant `:`). Sinon `jira_resolve_assignee <KEY> <nom>` interroge `GET /rest/api/3/user/assignable/search` avec `--get --data-urlencode` (l'encodage est délégué à curl, jamais fait à la main) :

- une correspondance → on l'utilise, et on dit lequel : `→ assigné à Alexandre Husset (6256cf…)` ;
- zéro → `⛔ aucun utilisateur assignable ne correspond à « X » sur <KEY>` ;
- plusieurs → refus, liste `displayName — accountId`, et rappel qu'un accountId est accepté directement.

**3. Déduplication des pièces jointes homonymes.** Le défaut est déjà arrivé sur RD-29 : deux pièces jointes nommées `cadrage-rd-29-erreurs-helpers-jira.md`, deux écritures au même chemin, la seconde écrase la première sans un mot, le compteur annonce trois fichiers pour deux écrits, et le survivant est la version périmée.

La métadonnée lue en `jira-download.sh:26` contient déjà l'`id` de chaque pièce jointe. Le flux `jq` en ligne 35 le remonte, et le script suffixe le nom en cas de collision **dans la même exécution** :

```
↓ jira-RD-29/conception.md
⚠ deuxième pièce jointe nommée « conception.md » → conception~10432.md
↓ jira-RD-29/conception~10432.md
✅ 2 pièce(s) jointe(s) récupérée(s)
```

**Bash 3.2 : pas de tableau associatif.** Les noms déjà vus sont tenus dans une variable multi-lignes, testée par `grep -Fxq`. Un nom de pièce jointe peut contenir des espaces : la comparaison se fait sur la ligne entière, jamais par découpage de mots.

**Le nom de pièce jointe est réduit à son `basename` avant tout usage.** `name` vient des métadonnées de l'API et atterrit aujourd'hui tel quel dans `${DEST}/${name}` : un nom contenant `/` (poussé par un autre client API — Jira ne normalise pas tout) écrirait **hors** du dossier de destination (`../../x` remonte l'arborescence). Défaut préexistant, mais cette conception réécrit exactement cette boucle : le corriger ici coûte une ligne (`basename`), le laisser serait la version sécurité du piège que ce document dénonce. Un cas du faux Jira sert un nom avec `/` et le test vérifie que le fichier reste **dans** `DEST`.

Le compteur n'est incrémenté qu'**après** une écriture réussie.

## Pas d'interface

Aucun écran, aucune maquette : le livrable est constitué de scripts en ligne de commande. Le seul artefact « visuel » est le format du message d'erreur, spécifié plus haut.

## Risques et cas limites

| Risque | Traitement |
|---|---|
| Le message d'erreur part sur stdout par inadvertance | `jira_report_http_error` écrit dans un bloc `{ … } >&2`. Test dédié : stdout vide sur un appel échoué |
| La garde de statut s'ouvre en silence | Test : `test_jira_guard.sh` inchangé et vert ; plus un cas où l'appel à Jira échoue et où la décision reste un JSON valide |
| Sortie de succès modifiée | Test de comparaison octet pour octet, avant/après, sur une lecture réussie |
| Fuite du jeton | Test : le jeton n'apparaît ni sur stdout ni sur stderr d'un appel échoué |
| Fichier temporaire laissé | `mv` en cas de succès, `rm -f` sur tous les chemins d'échec. Test : le dossier de destination ne contient aucun `.part.*` après un échec |
| Deux exécutions concurrentes de `jira-download.sh` | Le suffixe `mktemp` est unique par processus ; le `mv` est atomique sur le même système de fichiers |
| Budget de 6 s du hook | Aucun appel réseau supplémentaire, aucun fichier temporaire sur ce chemin (c'est la raison du choix « deux fonctions ») |
| Corps non-JSON (proxy, 401 sans corps) | Repli sur le code HTTP + 200 caractères. Test avec une réponse HTML |
| Bash 3.2 | `bash -n` sur le bash 3.2 du poste, et aucune syntaxe de bash 4 |
| Un appelant veut échouer en silence | `JIRA_QUIET_ERRORS=1`. Test des deux modes |
| Le pré-vol ferme une transition que le serveur accepte | Pré-vol limité à `worklog` (mesuré fatal) ; tout autre champ requis → tentative + remontée d'erreur. Test : `Annulé` avec `--worklog` seul → POST émis, rc=0 |
| Régression d'accent au remplacement de `jira_transition_id_for_status` | Correspondance dans jq (`ascii_upcase`), statut `Annulé` dans le faux Jira. Un `tr` shell passerait les tests ASCII et raterait la prod |
| Nom de pièce jointe contenant `/` | `basename` avant tout usage ; test : le fichier reste dans `DEST` |

## Plan d'implémentation

> **Pour l'exécution :** `/ezacae-dev:developer docs/conception/rd-29-remontee-erreurs-helpers-jira.md`

**Objectif :** rendre visible le message d'erreur de Jira sur tout chemin d'échec des helpers, sans changer un octet des chemins de succès.
**Architecture :** un seul point de passage (`jira_curl`) réécrit dans `jira-lib.sh`, une fonction sœur pour les écritures en fichier, trois appelants ajustés, une suite de tests hors-ligne.

Structure bug : **régression (RED) → correctif (GREEN) → non-régression**.

---

### Phase 1 — Régression (RED)

#### Tâche 1.1 : étendre le faux Jira
**Fichiers :** Modifier `plugins/ezacae-jira/tests/fake-jira.py`
- [ ] Ajouter les routes : `400` avec `errors` seul, `401` avec un corps HTML, `404` avec `errorMessages`, `204` sans corps, contenu de pièce jointe en succès (dont un binaire avec octet nul), et une liste de pièces jointes contenant **deux entrées de même nom** avec des `id` distincts + **une entrée dont le nom contient `/`** (cas basename)
- [ ] Ajouter la route transitions avec `expand` : un statut **accentué** (`Annulé`) requérant `worklog` **et** `resolution`, dont le POST **réussit** avec worklog seul (résolution par défaut serveur) ; un compteur de POST reçus consultable (`/post-count`)
- [ ] Vérifier à la main : `python3 fake-jira.py` démarre et imprime son port
- [ ] Commit

#### Tâche 1.2 : les cas rouges
**Fichiers :** Modifier `plugins/ezacae-jira/tests/test_jira_curl_errors.sh`
- [ ] Aligner le style sur `test_jira_guard.sh` (variable `HERE`, `set -uo pipefail`, comptage `PASS`/`FAIL` local)
- [ ] Écrire les assertions : message de Jira sur stderr pour chacune des quatre familles ; `errors` seul remonté ; corps HTML → code HTTP affiché ; stdout vide sur échec ; jeton absent des deux flux ; aucun `.part.*` laissé ; deux homonymes → deux fichiers distincts et compteur à 2
- [ ] Lancer : la suite doit être **rouge** sur les cas de message et de déduplication, **verte** sur les garde-fous déjà satisfaits (aucun fichier laissé, stdout vide)
- [ ] Conserver la sortie rouge comme preuve
- [ ] Commit

### Phase 2 — Correctif (GREEN)

#### Tâche 2.1 : `jira_report_http_error`
**Fichiers :** Modifier `plugins/ezacae-jira/scripts/jira-lib.sh`
- [ ] Implémenter : extraction de `errorMessages` **et** `errors`, itération ligne par ligne, repli non-JSON, `JIRA_QUIET_ERRORS`, tout sur stderr
- [ ] Lancer la suite : les cas de message passent au vert
- [ ] Commit

#### Tâche 2.2 : `jira_curl` sans `--fail`
**Fichiers :** Modifier `plugins/ezacae-jira/scripts/jira-lib.sh`
- [ ] Remplacer `--fail` par `--write-out '\n%{http_code}'` + décision sur le code ; rien sur stdout en cas d'échec
- [ ] Vérifier le cas `204` (corps vide) et un corps contenant des sauts de ligne
- [ ] Lancer la suite + `test_jira_guard.sh`
- [ ] Commit

#### Tâche 2.3 : `jira_curl_to_file` et bascule du téléchargement
**Fichiers :** Modifier `jira-lib.sh`, `jira-download.sh`
- [ ] Implémenter la fonction (temporaire voisin, `mv` seulement si 2xx, `rm -f` sinon)
- [ ] Remplacer `jira_curl -L "$url" -o …` (ligne 32) par l'appel à la nouvelle fonction
- [ ] Lancer la suite : aucun fichier laissé après échec, contenu binaire intact
- [ ] Commit

#### Tâche 2.4 : déduplication des homonymes + basename
**Fichiers :** Modifier `jira-download.sh`
- [ ] Réduire `name` à son `basename` avant tout usage (un nom avec `/` ne sort jamais de `DEST`)
- [ ] Remonter l'`id` dans le flux `jq` de la ligne 35 ; tenir la liste des noms vus (compatible bash 3.2, `grep -Fxq`) ; suffixer et **le dire** ; compter après écriture
- [ ] Lancer la suite : deux homonymes → deux fichiers, compteur juste, nom avec `/` confiné dans `DEST`
- [ ] Commit

#### Tâche 2.5 : indice `--worklog`
**Fichiers :** Modifier `jira-lib.sh` (ajout de `jira_transitions`, suppression de `jira_transition_id_for_status`), `jira-transition.sh`
- [ ] Un seul appel aux transitions avec `expand=transitions.fields` ; en tirer l'id **et** les champs requis
- [ ] La correspondance de statut cible reste **entièrement dans jq** (`ascii_upcase` des deux côtés — jamais `tr` shell, cf. le piège de locale documenté à `jira-lib.sh:49-52`)
- [ ] Pré-vol **worklog seulement** : requis + `--worklog` absent → refus avant envoi, message citant l'option, **aucun POST émis** (compteur du faux Jira)
- [ ] Tout autre champ requis manquant (`resolution`…) → **tenter le POST** et laisser la remontée d'erreur parler ; test : `Annulé` (worklog+resolution requis, défaut serveur) lancé avec `--worklog` seul → POST émis, rc=0
- [ ] Test de l'accent : la cible `annulé`/`ANNULÉ` matche le statut `Annulé` du faux Jira
- [ ] Commit

#### Tâche 2.6 : `--assignee` par nom d'affichage
**Fichiers :** Modifier `jira-lib.sh` (`jira_looks_like_account_id`, `jira_resolve_assignee`), `jira-edit.sh`
- [ ] Implémenter les trois cas : une correspondance, zéro, plusieurs
- [ ] Encoder la requête avec `--get --data-urlencode`, jamais à la main
- [ ] Mettre à jour la ligne d'usage (`jira-edit.sh:10`), qui annonce encore `<accountId|->`
- [ ] Tests hors-ligne des trois cas
- [ ] Commit

### Phase 3 — Non-régression

#### Tâche 3.1 : les chemins de succès, octet pour octet — par fixtures d'or
**Fichiers :** Modifier `plugins/ezacae-jira/tests/test_jira_curl_errors.sh`, créer `plugins/ezacae-jira/tests/fixtures/rd29/`
- [ ] Figer en fixtures commitées la sortie **attendue** d'une lecture réussie (corps JSON servi par le faux Jira → sortie exacte du helper) et un contenu binaire de pièce jointe (avec octet nul) ; `cmp` contre la fixture doit être silencieux
- [ ] Ne pas capturer d'état « avant » à l'exécution (`git stash`/checkout au milieu d'une suite : fragile, et le worktree de developer n'a pas d'« avant ») — la fixture d'or **est** la référence, relue par la revue
- [ ] Commit

#### Tâche 3.2 : preuves fraîches
- [ ] `bash -n` sur les cinq scripts modifiés, avec le bash 3.2 du poste
- [ ] `bash plugins/ezacae-jira/tests/test_jira_guard.sh` → `PASS=n FAIL=0`
- [ ] `bash plugins/ezacae-jira/tests/test_jira_curl_errors.sh` → `FAIL=0`
- [ ] `bash plugins/ezacae-dev/tests/test-check-superpowers.sh` et les deux tests d'invariant de RD-27 → inchangés
- [ ] Une vérification manuelle contre le vrai Jira, documentée dans la MR : une lecture réussie, et un échec qui affiche le message (par exemple une clé inexistante)
- [ ] Vérifier la fusion à blanc avec RD-23 : `git merge-tree --write-tree origin/rd-23-cadrage-mise-en-forme-jira <branche>` — coller le résultat dans la MR
- [ ] Commit

## Ce que cette conception ne fait pas

- **Ne touche pas `jira-get.sh`** : RD-23 le modifie, on reste indépendant de l'ordre de fusion.
- **N'ajoute pas la suppression de pièce jointe** : ce manque produit les doublons de nom, mais c'est une opération nouvelle, hors périmètre (ticket à part).
- **Ne traduit pas les erreurs au-delà des deux cas demandés** (worklog, assigné). Les autres 4xx affichent le message de Jira, sans phrase d'aide ajoutée.
- **Ne réécrit pas la garde de statut** ni le hook.
- **N'introduit pas le harnais de test commun de RD-23** : la suite garde son propre comptage, pour rester fusionnable dans n'importe quel ordre.
