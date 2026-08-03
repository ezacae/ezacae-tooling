# Cadrage — Les helpers JIRA masquent le message d'erreur de Jira (RD-29)

Statut : Actif — cadrage fonctionnel, entrée de la phase de conception (chuck).

## Le problème

Quand une opération JIRA échoue, l'utilisateur ne voit pas pourquoi. Il voit `curl: (56) The requested URL returned error: 400`. Jira, lui, avait envoyé une phrase claire qui disait la cause et souvent le remède. Cette phrase est jetée avant d'atteindre l'écran.

Le coût est direct : deux fois le 31/07 pendant RD-21, il a fallu rappeler l'API à la main pour apprendre que le temps consacré était obligatoire, puis que le champ assigné attendait un identifiant technique. Deux informations que Jira avait données du premier coup.

Le mode de panne est de la même famille que RD-22 : l'outil sait quelque chose d'utile et ne le dit pas. Ici il ne s'agit pas de détecter, mais seulement d'afficher ce qui est déjà là.

## Ce qu'on a vérifié

Reproduit le 03/08 sur le poste courant (curl 8.7.1), trois erreurs de nature différente, deux lectures et une écriture :

| Appel | Ce que le helper affiche | Ce que Jira avait répondu |
|---|---|---|
| GET, JQL invalide (400) | `curl: (56) ... error: 400` | « Erreur dans la requête JQL : un nom de champ est anticipé mais `(` est mentionné à la place (ligne 1, caractère 10) » |
| GET, ticket inexistant (404) | `curl: (56) ... error: 404` | « Le ticket n'existe pas ou vous n'êtes pas autorisé à la voir. » |
| POST, id de transition invalide (400) | `curl: (56) ... error: 400` | « Transition id '999999' is not valid for this issue. » |
| PUT, `assignee` = nom d'affichage (400) | `curl: (56) ... error: 400` | `{"errorMessages":[],"errors":{"assignee":"Spécifiez une valeur valide pour assignee"}}` |

Quatre faits à en retenir.

1. **Un seul point à corriger.** Tous les appels réseau des onze helpers passent par `jira_curl` (`plugins/ezacae-jira/scripts/jira-lib.sh:35`) — vérifié, aucun `curl` construit ailleurs, pièces jointes comprises. Le correctif est à un seul endroit et couvre tout.
2. **Le défaut touche aussi les lectures.** Le ticket d'origine visait les POST et PUT. Un `jira-get.sh` sur une clé inconnue ou sans droit d'accès est tout aussi muet. La correction porte sur `jira_curl`, sans distinction de méthode.
3. **Deux champs, pas un.** L'échec d'assignation laisse `errorMessages` vide et met tout dans `errors`. N'afficher que le premier laisserait ce cas — celui qui a fait perdre du temps sur RD-21 — exactement aussi muet qu'aujourd'hui.
4. **Le code de sortie observé est 56, pas 22.** curl coupe la connexion après `--fail`, d'où `CURLE_RECV_ERROR`. Aucun script ne teste cette valeur (vérifié) : ils ne distinguent que succès et échec. La valeur exacte du code est donc libre, à condition de rester non nulle.

## La contrainte qui commande tout : à qui appartient stdout

`jira-lib.sh` n'est pas sourcé que par les scripts. Le hook `PreToolUse` `jira-guard.sh` le source aussi, et appelle `jira_status` — donc `jira_curl` — pour lire le statut courant du ticket. Ce hook **écrit sa décision en JSON sur stdout**, que le CLI parse. L'avertissement est déjà en tête du fichier, lignes 8-9.

Un message d'erreur écrit sur stdout casserait donc la garde de statut du pipeline à chaque 4xx ou coupure réseau rencontrée par le hook : au lieu d'une décision JSON, le CLI recevrait du texte. Même exigence côté scripts de lecture, dont le stdout est consommé par `jq`.

**Donc : le message part sur stderr, sans exception.** C'est la contrainte principale de ce ticket, et elle ne figurait pas dans sa rédaction initiale.

Corollaire pour la conception : le hook baisse volontairement le budget de temps (`JIRA_CURL_MAX_TIME=6`, `jira-guard.sh:32`). Le chemin d'erreur ne doit rien ajouter à ce budget — ni nouvel appel réseau pour « aller chercher » le message, ni attente supplémentaire.

## Périmètre

**`jira_curl` dans `jira-lib.sh`** — le point unique. Sur échec, afficher `errorMessages` et `errors` du corps de la réponse sur stderr, puis sortir en erreur.

**Les onze helpers en bénéficient sans être modifiés** : `jira-get`, `jira-comment`, `jira-transition`, `jira-edit`, `jira-attach`, `jira-download`, `jira-create`, `jira-search`, `jira-projects`, `jira-link`.

**Deux messages ciblés en plus**, parce que ce sont les deux cas réellement rencontrés :

- **`jira-transition.sh`** — quand Jira réclame le temps consacré, citer l'option `--worklog` dans le message. L'exigence est déjà documentée (skill `jira-pipeline` §5, trois transitions concernées) ; ce qui manque, c'est de le dire au moment où ça échoue, pas dans un document qu'on lit avant.
- **`jira-edit.sh --assignee`** — accepter un nom d'affichage, ou refuser en nommant la cause. L'endpoint de résolution a été vérifié : `/rest/api/3/user/assignable/search?issueKey=RD-29&query=Alexandre` renvoie bien `Alexandre Husset` et son `accountId`. **Piège mesuré** : une requête vide renvoie 10 utilisateurs. Plusieurs correspondances ne doivent jamais être tranchées en silence — assigner le mauvais collègue sans le dire serait pire que l'échec actuel.

**Tests hors-ligne**, sur le modèle de `tests/test_jira_guard.sh` (zéro appel réseau, seul `jq` requis). Les cas viennent de ce qui a été observé, pas d'un catalogue : corps avec `errorMessages` seul, corps avec `errors` seul, les deux vides, corps non-JSON (page HTML d'un proxy), corps vide, échec sans réponse du tout (timeout).

**Hors périmètre** : la mise en forme du contenu écrit dans Jira (RD-23) ; l'ajout de nouvelles opérations aux helpers ; toute reprise automatique d'un appel échoué ; la réécriture de la garde de statut.

## Qui est impacté

- **Le développeur en ligne de commande** — bénéficiaire direct. Aujourd'hui il rappelle l'API à la main pour lire ce que l'outil avait déjà reçu.
- **Les agents du pipeline** (Mike, Sarah et les rôles qu'ils appellent) — première victime, moins visible. Face à un code de sortie sans cause, un agent ne peut que deviner ou abandonner. Avec le message, il peut se corriger seul : c'est le cas d'usage du `--worklog` manquant.
- **Le `jira-watcher`** en tâche planifiée — il tourne sans personne devant l'écran. Ses journaux ne contiennent aujourd'hui que des codes de sortie. Son image est `node:22-bookworm-slim` avec `curl` de Debian bookworm (7.88) : toute option retenue doit y exister, pas seulement sur le curl 8.7.1 du poste.
- **Le hook de garde `jira-guard.sh`** — non bénéficiaire mais partie exposée : c'est lui que le choix du canal de sortie peut casser.

## Processus concernés

- **Toute opération JIRA du pipeline** — chaque transition, commentaire, pièce jointe, édition passe par ce chemin.
- **Le diagnostic d'un échec** — c'est le processus que ce ticket crée : aujourd'hui il faut sortir de l'outil pour comprendre.
- **La garde de statut à chaque appel MCP intercepté** — à ne pas casser (cf. contrainte sur stdout).

## Contraintes connues

1. **Le message part sur stderr**, jamais stdout. Le stdout du hook est un JSON parsé ; celui des lectures est consommé par `jq`.
2. **Les chemins de succès sont inchangés, au caractère près.** C'est la garantie qui permet de corriger un point traversé par onze scripts sans les relire un par un.
3. **Le code de sortie reste non nul.** La détection fonctionne déjà ; seul l'affichage manque. La valeur exacte est libre : aucun appelant ne la teste.
4. **Pas de second appel réseau** pour récupérer le message. Le corps arrive avec la réponse ; il suffit de ne plus le jeter. Un appel de rattrapage doublerait le coût et sortirait du budget de 6 secondes du hook.
5. **Un corps peut ne pas être du JSON, ou être vide.** Proxy d'entreprise, 401 sans corps, coupure réseau avant la réponse. Dans ces cas le message doit rester utile — au minimum le code HTTP et l'URL appelée — et ne jamais faire échouer le helper d'une autre façon que l'échec d'origine.
6. **Compatibilité curl entre le poste et l'image du watcher** : Debian bookworm (7.88) et macOS (8.7.1). Toute option retenue doit exister dans les deux.
7. **Aucun secret dans la sortie d'erreur.** Le jeton API est passé en `-u` sur la ligne de commande de `curl`. Un message qui recopierait la commande ou les en-têtes fuiterait le jeton dans la conversation, dans les journaux du watcher, et dans le ticket si un agent le recopie. À vérifier explicitement par un test.
8. **Tests hors-ligne obligatoires.** Réponses simulées, aucun appel réseau, sur le modèle de `test_jira_guard.sh`.
9. **`test_jira_guard.sh` doit continuer de passer** : c'est le garde-fou qui prouve que la garde et la redirection MCP survivent au changement.

## Ce qui reste à trancher en conception

Ces points relèvent de chuck, pas du cadrage.

- **Comment récupérer le corps sans le laisser fuir sur stdout.** Deux familles : remplacer `--fail` par `--fail-with-body` (présent dans les deux curl, mais il écrit le corps sur stdout — il faut donc le rediriger sans casser le stdout de succès), ou abandonner `--fail` et décider soi-même à partir du code HTTP (`-w`, corps dans un fichier temporaire). Le second est plus verbeux mais met le canal sous contrôle explicite. À trancher, avec la contrainte 2 comme juge.
- **La forme exacte du message.** Une ligne pour l'usage courant, contre un pavé qui noiera le signal — sachant que la sortie d'un hook part en contexte d'agent (même arbitrage que RD-22, contrainte 10).
- **Faut-il nommer le remède au-delà du worklog ?** Le cas du worklog est explicitement demandé. Les autres 4xx récurrents (401 jeton expiré, 403 droits, 404 clé inconnue) mériteraient peut-être la même phrase d'aide. Décider où s'arrête la traduction, plutôt que de la laisser grandir au fil des tickets.
- **La résolution du nom d'affignage en `accountId`** : geste automatique, ou refus explicite avec la commande à lancer ? Et que faire des correspondances multiples — refuser en listant, ou demander. Le refus explicite est le comportement sûr ; la résolution automatique est plus agréable et déjà validée techniquement. Un homonyme ne doit pas produire une assignation silencieusement fausse.
- **Un fichier temporaire est-il acceptable dans le hook ?** Si l'implémentation en passe par là, le hook s'exécute à chaque appel d'outil : nettoyage et absence de course sont à traiter.

## Dépendances

- **RD-27** — origine du constat, dans ses commentaires de passation. Son objet propre est livré et fusionné ; seul le défaut d'outillage qu'il signalait en passant reste ouvert, et c'est ce ticket.
- **RD-23 (mise en forme Jira)** — en `Examiner`, aucun recouvrement fonctionnel, mais les deux touchent `plugins/ezacae-jira/scripts/`, dont `jira-get.sh`. Conflit de fusion probable si les branches vivent en parallèle : ordonner les deux fusions plutôt que les découvrir.
- **RD-28 (aucun pipeline de merge request ne se déclenche)** — les tests demandés ici ne tourneront pas en CI tant qu'il n'est pas traité. Ils doivent rester lançables à la main, et la preuve de leur passage être fournie dans la merge request.
- **RD-13 (socle harnais)** — indépendant. Le défaut est dans l'outillage existant, quelle que soit la piste retenue.

## Contournement en attendant

Rejouer l'appel échoué sans `--fail` pour lire le corps de la réponse. C'est ce qui a été fait sur RD-21, puis à nouveau ici pour rédiger ce cadrage — trois fois le même détour manuel pour une information que l'outil avait déjà en main.
