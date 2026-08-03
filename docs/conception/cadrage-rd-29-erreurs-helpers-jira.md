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

Cinq faits à en retenir.

1. **Un seul point à corriger.** Tous les appels réseau des onze helpers passent par `jira_curl` (`plugins/ezacae-jira/scripts/jira-lib.sh:35`) — vérifié, aucun `curl` construit ailleurs, pièces jointes comprises. Le correctif est à un seul endroit et couvre tout.
2. **Le défaut touche aussi les lectures.** Le ticket d'origine visait les POST et PUT. Un `jira-get.sh` sur une clé inconnue ou sans droit d'accès est tout aussi muet. La correction porte sur `jira_curl`, sans distinction de méthode.
3. **Deux champs, pas un.** L'échec d'assignation laisse `errorMessages` vide et met tout dans `errors`. N'afficher que le premier laisserait ce cas — celui qui a fait perdre du temps sur RD-21 — exactement aussi muet qu'aujourd'hui.
4. **La détection d'échec, elle, fonctionne déjà.** Les onze scripts portent `set -euo pipefail`, donc un `jira_curl | jq` ne masque pas l'échec ; `jira-attach.sh:27` jette sa sortie et `jira-get.sh:30` la capture avant de la passer à `jq`. Il n'y a bien que l'affichage à ajouter.
5. **Le code de sortie dépend du transport, pas de notre code.** Contre Atlassian en HTTPS, `--fail` produit 56 (`CURLE_RECV_ERROR`, curl coupe la connexion) ; contre un serveur HTTP local, le même échec produit 22. Aucun script ne teste cette valeur (vérifié) : elle est libre, à condition de rester non nulle. **Conséquence directe : aucun test hors-ligne ne peut asserter « plus de code 56 ».** Un test local verrait 22 et passerait sans rien prouver. L'invariant testable est la *présence du message de Jira sur stderr*, jamais l'absence d'un numéro. Le critère d'acceptation du ticket a été reformulé en conséquence.

## Le piège qui casse un cas propre : l'écriture directe en fichier

`jira-download.sh:32` écrit le contenu d'une pièce jointe directement dans un fichier : `jira_curl -L "$url" -o "${DEST}/${name}"`. C'est le seul appel dont la sortie n'est ni du JSON ni jetée.

Le chemin de correction le plus court — remplacer `--fail` par `--fail-with-body` — **y introduit une corruption silencieuse**. Mesuré sur un faux Jira local :

| Variante | Code de sortie | Fichier de destination |
|---|---|---|
| `--fail -o` (aujourd'hui) | 22 | **aucun fichier créé** |
| `--fail-with-body -o` | 22 | **fichier créé, 101 octets**, contenant `{"errorMessages":["Le ticket n'existe pas ou vous n'êtes pas autorisé à la voir."],"errors":{}}` |

Scénario : Mike en phase doc finale lance `jira-download.sh RD-29 /tmp/jira-RD-29`. Le jeton a expiré, ou une pièce jointe a été supprimée entre-temps. Un fichier `conception.md` apparaît, de 101 octets, contenant le message d'erreur. `set -euo pipefail` interrompt la boucle : le dossier contient donc un mélange de vraies pièces jointes et d'un faux document. Mike, puis Sarah, lisent ensuite ce dossier comme la conception livrée.

Autre variante à écarter pour la même raison : bufferiser le corps dans une variable shell. Les pièces jointes ne sont pas toutes du texte, et un octet nul tronque une variable bash sans prévenir.

**Donc : le cas « sortie vers un fichier » se traite à part, et un téléchargement échoué ne doit laisser aucun fichier derrière lui.** C'est aujourd'hui un cas propre ; la seule façon de le casser est de le corriger sans y penser.

### Le même invariant, cassé aujourd'hui : deux pièces jointes de même nom

Ce n'est pas une hypothèse, c'est arrivé sur ce ticket. RD-29 portait deux pièces jointes nommées `cadrage-rd-29-erreurs-helpers-jira.md` — la version initiale et la version corrigée. La boucle de `jira-download.sh:29-35` écrit chaque pièce jointe à `${DEST}/${name}` : deux noms identiques, deux écritures au même chemin, la seconde écrase la première **sans un mot**. Sortie observée :

```
↓ /tmp/jira-RD-29/cadrage-rd-29-erreurs-helpers-jira.md
↓ /tmp/jira-RD-29/cadrage-rd-29-erreurs-helpers-jira.md     ← même chemin
↓ /tmp/jira-RD-29/test_jira_curl_errors.sh
✅ 3 pièce(s) jointe(s) récupérée(s)
```

Le compteur annonce trois fichiers, le dossier en contient deux, et le survivant est celui que l'ordre de l'API a désigné — en l'occurrence **la version périmée**. Sarah, qui prend la fiche téléchargée comme source de vérité, a conçu à partir du mauvais document jusqu'à ce que la vérification l'attrape.

C'est exactement l'invariant du bloquant ci-dessus, à la même ligne du même script : **un téléchargement ne doit jamais produire silencieusement un fichier faux**. Deux visages du même défaut, corrigés d'un geste.

Le minimum est de ne pas mentir : soit refuser, soit dédupliquer le nom (suffixe par l'id de la pièce jointe, disponible dans les métadonnées déjà lues ligne 26), et dans tous les cas le dire. Le compteur final doit compter des fichiers réellement écrits.

Note de terrain : il n'existe aucun helper pour **supprimer** une pièce jointe, donc corriger un document attaché impose soit un nom versionné, soit un passage par l'interface Jira. Ce manque est hors périmètre ici, mais il alimente le défaut : c'est lui qui produit les doublons de nom.

## La contrainte qui commande tout : à qui appartient stdout

`jira-lib.sh` n'est pas sourcé que par les scripts. Le hook `PreToolUse` `jira-guard.sh` le source aussi, et appelle `jira_status` — donc `jira_curl` — pour lire le statut courant du ticket. Ce hook **écrit sa décision en JSON sur stdout**, que le CLI parse. L'avertissement est déjà en tête du fichier, lignes 8-9.

Le mécanisme exact mérite d'être décrit juste, parce que la conséquence n'est pas celle qu'on croit. Le hook fait `CUR=$(jira_status "$KEY" 2>/dev/null || true)` (`jira-guard.sh:105`) : stdout est **capturé** par la substitution de commande, et stderr est déjà jeté. Un message d'erreur écrit sur stdout n'atteint donc pas le CLI — il atterrit dans la variable de statut, `jq` n'en tire rien, et la ligne suivante applique `[ -z "$CUR" ] && allow`.

**La garde ne casse pas : elle s'ouvre en silence.** Même schéma lignes 112-115 pour la résolution du statut cible. Scénario : un 500 ou un timeout pendant une transition, et une transition hors séquence est autorisée sans que personne ne le voie. C'est pire qu'un plantage, qui au moins se remarque.

**Donc : le message part sur stderr, sans exception.** C'est la contrainte principale de ce ticket, et elle ne figurait pas dans sa rédaction initiale. Même exigence côté scripts de lecture, dont le stdout est consommé par `jq`.

Corollaire pour la conception : le hook baisse volontairement le budget de temps (`JIRA_CURL_MAX_TIME=6`, `jira-guard.sh:32`). Le chemin d'erreur ne doit rien ajouter à ce budget — ni nouvel appel réseau pour « aller chercher » le message, ni attente supplémentaire.

## Périmètre

**`jira_curl` dans `jira-lib.sh`** — le point unique. Sur échec, afficher `errorMessages` et `errors` du corps de la réponse sur stderr, puis sortir en erreur.

**Les onze helpers en bénéficient sans être modifiés** : `jira-get`, `jira-comment`, `jira-transition`, `jira-edit`, `jira-attach`, `jira-download`, `jira-create`, `jira-search`, `jira-projects`, `jira-link`.

**Deux messages ciblés en plus**, parce que ce sont les deux cas réellement rencontrés :

- **`jira-transition.sh`** — citer l'option `--worklog` quand la transition l'exige. L'exigence est déjà documentée (skill `jira-pipeline` §5, trois transitions concernées) ; ce qui manque, c'est de le dire au moment où ça échoue, pas dans un document qu'on lit avant. **Ne pas le déduire du texte du message** : Jira répond dans la langue du compte, et « Le temps consacré est obligatoire » devient « Time spent is required » pour un collègue dont le profil est en anglais — la suggestion ne se déclencherait pas, et on serait revenu au point de départ. La route stable est déjà à portée : `GET /rest/api/3/issue/<KEY>/transitions?expand=transitions.fields` liste les champs requis par nom technique, indépendamment de la langue. Mesuré sur RD-29 : `Conception terminée → CONCEPTION VALIDATION | ecran=true | requis: worklog`. Et `jira_transition_id_for_status` (`jira-lib.sh:53-57`) **appelle déjà cette route** : ajouter `expand` coûte zéro requête et permet d'avertir *avant* de tenter la transition, sans lire aucun message d'erreur.
- **`jira-edit.sh --assignee`** — accepter un nom d'affichage, ou refuser en nommant la cause. L'endpoint de résolution a été vérifié : `/rest/api/3/user/assignable/search?issueKey=RD-29&query=Alexandre` renvoie bien `Alexandre Husset` et son `accountId`. **Piège mesuré** : une requête vide renvoie 10 utilisateurs. Plusieurs correspondances ne doivent jamais être tranchées en silence — assigner le mauvais collègue sans le dire serait pire que l'échec actuel.

**Tests hors-ligne**, avec leur propre comptage `PASS`/`FAIL` comme `tests/test_jira_guard.sh` (aucun appel sortant). Les cas viennent de ce qui a été observé, pas d'un catalogue : corps avec `errorMessages` seul, corps avec `errors` seul, les deux vides, corps non-JSON (page HTML d'un proxy), corps vide, échec sans réponse du tout (timeout), et **téléchargement échoué sans fichier laissé derrière**.

Une amorce est livrée avec ce cadrage : `tests/test_jira_curl_errors.sh` et `tests/fake-jira.py` (un faux Jira sur `127.0.0.1`, port éphémère, aucun credential réel). Lancée en l'état, elle donne `PASS=3 FAIL=2` : les deux échecs sont le défaut à corriger, les trois succès sont des garde-fous de non-régression — le fichier absent après un téléchargement raté, et le stdout resté vide. Le correctif naïf les fait passer au rouge, ce qui est exactement leur raison d'être.

**`jira-download.sh`** — les deux visages de l'invariant « pas de fichier faux » : aucun fichier laissé après un échec, et pas d'écrasement silencieux entre deux pièces jointes homonymes.

**Hors périmètre** : la mise en forme du contenu écrit dans Jira (RD-23) ; l'ajout de nouvelles opérations aux helpers, dont la **suppression de pièce jointe** qui manque aujourd'hui ; toute reprise automatique d'un appel échoué ; la réécriture de la garde de statut.

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
3. **Le code de sortie reste non nul.** La détection fonctionne déjà ; seul l'affichage manque. La valeur exacte est libre : aucun appelant ne la teste. Corollaire : **aucun test ne doit asserter un numéro de code** (56 en HTTPS, 22 en HTTP local — cf. fait 5).
4. **Un téléchargement ne produit jamais silencieusement un fichier faux.** Deux cas, même ligne (`jira-download.sh:32`), seul appel qui écrit hors JSON : un échec ne laisse aucun fichier à la destination (ni vide, ni porteur du JSON d'erreur), et deux pièces jointes de même nom ne s'écrasent pas en silence. Le compteur final compte des fichiers réellement écrits.
5. **Un message par échec, pas deux.** `jira-transition.sh:34` et `:45` impriment déjà leur propre diagnostic (statut introuvable, liste des transitions disponibles). Un bloc brut posé au-dessus donnerait deux messages pour une seule erreur, et le second est le plus utile.
6. **Un appelant doit pouvoir se taire.** L'affichage centralisé s'impose à tous, y compris à ceux qui *attendent* un échec (sondes, recherches optionnelles du hook). Le hook n'y échappe aujourd'hui que parce qu'il redirigeait déjà stderr — c'est un hasard heureux, pas un choix de conception.
7. **Pas de second appel réseau** pour récupérer le message. Le corps arrive avec la réponse ; il suffit de ne plus le jeter. Un appel de rattrapage doublerait le coût et sortirait du budget de 6 secondes du hook.
8. **Un corps peut ne pas être du JSON, ou être vide.** Proxy d'entreprise, 401 sans corps, coupure réseau avant la réponse. Dans ces cas le message doit rester utile — au minimum le code HTTP et l'URL appelée — et ne jamais faire échouer le helper d'une autre façon que l'échec d'origine.
9. **Compatibilité curl entre le poste et l'image du watcher** : Debian bookworm (7.88) et macOS (8.7.1). Toute option retenue doit exister dans les deux.
10. **Aucun secret dans la sortie d'erreur.** Le jeton API est passé en `-u` sur la ligne de commande de `curl`. Un message qui recopierait la commande ou les en-têtes fuiterait le jeton dans la conversation, dans les journaux du watcher, et dans le ticket si un agent le recopie. À vérifier explicitement par un test.
11. **Tests hors-ligne obligatoires**, avec leur propre comptage `PASS`/`FAIL`. Réponses simulées, aucun appel sortant.
12. **`test_jira_guard.sh` doit continuer de passer** : c'est le garde-fou qui prouve que la garde et la redirection MCP survivent au changement.

## Ce qui reste à trancher en conception

Ces points relèvent de chuck, pas du cadrage.

- **Comment récupérer le corps sans le laisser fuir là où il ne doit pas aller.** Deux familles : remplacer `--fail` par `--fail-with-body` (présent dans les deux curl, mais il écrit le corps là où va la sortie — sur stdout pour les lectures, **et dans le fichier de destination pour `jira-download.sh`**, cf. le piège ci-dessus), ou abandonner `--fail` et décider soi-même à partir du code HTTP (`-w`, corps dans un fichier temporaire). Le second est plus verbeux mais met le canal sous contrôle explicite. À trancher, avec les contraintes 2 et 4 comme juges. Si `--fail-with-body` est retenu, le cas `-o` doit être traité à part, sans exception.
- **La forme exacte du message.** Une ligne pour l'usage courant, contre un pavé qui noiera le signal — sachant que la sortie d'un hook part en contexte d'agent (même arbitrage que RD-22, contrainte 10).
- **Faut-il nommer le remède au-delà du worklog ?** Le cas du worklog est explicitement demandé. Les autres 4xx récurrents (401 jeton expiré, 403 droits, 404 clé inconnue) mériteraient peut-être la même phrase d'aide. Décider où s'arrête la traduction, plutôt que de la laisser grandir au fil des tickets.
- **La résolution du nom d'affignage en `accountId`** : geste automatique, ou refus explicite avec la commande à lancer ? Et que faire des correspondances multiples — refuser en listant, ou demander. Le refus explicite est le comportement sûr ; la résolution automatique est plus agréable et déjà validée techniquement. Un homonyme ne doit pas produire une assignation silencieusement fausse.
- **Un fichier temporaire est-il acceptable dans le hook ?** Si l'implémentation en passe par là, le hook s'exécute à chaque appel d'outil : nettoyage et absence de course sont à traiter.

## Dépendances

- **RD-27** — origine du constat, dans ses commentaires de passation. Son objet propre est livré et fusionné ; seul le défaut d'outillage qu'il signalait en passant reste ouvert, et c'est ce ticket.
- **RD-23 (mise en forme Jira)** — en `Examiner`, aucun recouvrement fonctionnel. **Ce ticket ne doit pas dépendre de l'ordre de fusion**, parce que la validation de cette merge request ne nous appartient pas. Trois règles rendent RD-29 indifférent à cet ordre, chacune mesurée :
  1. **Ne toucher que `jira_curl`, ligne 35 de `jira-lib.sh`.** L'unique modification de RD-23 dans ce fichier commence ligne 106 (`@@ -106,12 +106,172 @@`). Deux zones distinctes, fusion automatique.
  2. **Ne pas toucher `jira-get.sh`.** RD-23 le modifie ; RD-29 n'en a pas besoin, le correctif est en amont dans la fonction commune.
  3. **Tests dans leur propre fichier, avec leur propre comptage.** Ne pas importer le cadre de test `harness.sh` introduit par RD-23 : il n'existe pas encore sur la branche principale. Basculer dessus après sa fusion est un remplacement de trois lignes.

  Preuve à joindre à la merge request, sans écriture : `git merge-tree --write-tree origin/rd-23-cadrage-mise-en-forme-jira origin/rd-29-…`. Lancée au cadrage : fusion propre, aucun conflit. À relancer une fois le code écrit.

  Reste un point que l'ordre ne règle pas : les deux tickets promettent « la sortie normale ne change pas, au caractère près », chacun mesuré par rapport à l'état actuel. Si RD-23 est fusionnée entre-temps, la preuve de RD-29 doit être **relancée** sur la nouvelle base. C'est une relance de test, pas une reconception.
- **RD-28 (aucun pipeline de merge request ne se déclenche)** — les tests demandés ici ne tourneront pas en CI tant qu'il n'est pas traité. Ils doivent rester lançables à la main, et la preuve de leur passage être fournie dans la merge request.
- **RD-13 (socle harnais)** — indépendant. Le défaut est dans l'outillage existant, quelle que soit la piste retenue.

## Contournement en attendant

Rejouer l'appel échoué sans `--fail` pour lire le corps de la réponse. C'est ce qui a été fait sur RD-21, puis à nouveau ici pour rédiger ce cadrage — trois fois le même détour manuel pour une information que l'outil avait déjà en main.
