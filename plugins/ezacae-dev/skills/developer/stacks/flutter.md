# Conventions de stack — Flutter (Dart)

> **Bibliothèque de conventions du skill `developer` — entrée `flutter`.** Chargé automatiquement quand la détection de stack identifie un projet Flutter (`pubspec.yaml` contenant `flutter:`). Contient les conventions **génériques** Flutter / Dart valables pour toute application ezacae sur cette stack.
>
> **Spécificités d'une application donnée** (palette/thème maison, catalogue de widgets et de providers métier, schéma de données propre au projet, intégrations) **ne sont pas ici** : elles vivent dans le `CLAUDE.md` à la racine du repo applicatif, chargé en complément. En cas de conflit, **le `CLAUDE.md` du projet prime**.
>
> Commandes de vérification de cette stack : `dart format .`, `flutter analyze`, `flutter test`, `flutter build <cible>` — dépendances via `flutter pub get`.

---

## 1. Stack & versions

- **Framework** : Flutter (≥ 3.38.5, canal `stable`)
- **Langage** : Dart ≥ 3.4, **null-safety obligatoire**, records & patterns autorisés
- **Gestion de paquets** : `pub` (`flutter pub get`, versions verrouillées via `pubspec.lock` commité pour les apps)
- **State management** : un seul choix par projet, défini dans `CLAUDE.md` (Riverpod recommandé ; Bloc/Cubit accepté). Pas de mélange.
- **Navigation** : `go_router` (routing déclaratif, deep links)
- **Réseau** : `dio` (ou `http`) encapsulé dans une couche client typée
- **Modèles immuables** : `freezed` + `json_serializable` pour la (dé)sérialisation
- **Injection de dépendances** : via le state manager (Riverpod providers) ou `get_it`
- **Lints** : `very_good_analysis` (ou `flutter_lints` au minimum) dans `analysis_options.yaml`
- **Tests** : `flutter_test` (unitaires + widgets), `integration_test` (e2e), `mocktail` pour les mocks

---

## 2. Architecture & organisation du code

### 2.1 Structure recommandée (découpage par feature)

```
lib/
├── main.dart                     # Point d'entrée + bootstrap
├── app.dart                      # MaterialApp / routerConfig
├── core/                         # Transverse, sans dépendance aux features
│   ├── config/                   # env, flavors, constantes
│   ├── error/                    # Failure, exceptions typées
│   ├── network/                  # client dio, intercepteurs
│   ├── router/                   # go_router
│   ├── theme/                    # ThemeData, tokens
│   └── utils/
├── features/
│   └── <feature>/
│       ├── data/                 # data sources, DTO, repositories impl
│       ├── domain/               # entities, repositories (abstraits), use cases
│       └── presentation/         # widgets/pages + state (providers/blocs)
└── shared/                       # widgets & helpers réutilisables inter-features
test/                             # miroir de lib/
integration_test/
```

### 2.2 Règles structurelles

- **Découpage par feature**, pas par type technique global. Chaque feature est autonome (`data` / `domain` / `presentation`).
- **`domain` ne dépend de rien** (pur Dart) ; `data` implémente les contrats du `domain` ; `presentation` consomme le `domain`.
- **Pas de logique métier dans les widgets** — elle vit dans les use cases / notifiers / blocs.
- **Pas d'accès réseau ou BDD direct depuis un widget** — toujours via repository.
- **Widgets en classes**, jamais de fonctions qui retournent des `Widget` (casse `const`, le rebuild et le devtools). Extraire un `StatelessWidget`/`StatefulWidget`.
- **Privilégier `const`** sur les constructeurs de widgets dès que possible (perf de rebuild).

### 2.3 Découpage des widgets

- **Un widget fait UNE chose.** Au-delà de ~200 lignes ou de 2 niveaux d'imbrication complexes → extraire.
- Préférer la composition à l'héritage. Pas de `build()` monolithique.

---

## 3. Nommage

| Élément | Convention | Exemple |
|---|---|---|
| Fichier Dart | `snake_case.dart` | `user_card.dart` |
| Classe / type / enum | `UpperCamelCase` | `UserCard`, `AuthState` |
| Variable / fonction / paramètre | `lowerCamelCase` | `getUserById` |
| Constante | `lowerCamelCase` | `defaultPageSize` |
| Membre privé | préfixe `_` | `_controller` |
| Provider Riverpod | `<nom>Provider` | `currentUserProvider` |
| Dossier | `snake_case` | `features/user_profile/` |

- Nommer les widgets par ce qu'ils **sont** (`UserCard`), pas par ce qu'ils utilisent.
- Booléens : `isLoading`, `hasError`, `canEdit`.
- Pas d'abréviations sauf universelles (`id`, `url`, `http`).
- Imports : préférer les imports `package:` absolus aux chemins relatifs profonds.

---

## 4. Mutualisation & homogénéité

- **`shared/`** : widgets et helpers réutilisés par plusieurs features (boutons, champs, états vides/erreur).
- **`core/`** : code transverse sans dépendance feature.
- **Thème centralisé** dans `core/theme/` — couleurs, typographies, spacing via `ThemeData`/`ColorScheme`. **Aucune couleur ni taille en dur** dans les widgets : passer par `Theme.of(context)`.
- **Modèles immuables** générés (`freezed`) — pas de classes mutables pour l'état ou les DTO.
- **Types dérivés des schémas JSON** via `json_serializable` (`fromJson`/`toJson` générés, jamais écrits à la main).

---

## 5. Gestion d'état (state management)

- **Un seul système par projet** (défini dans `CLAUDE.md`). Riverpod recommandé.
- **État immuable** : modéliser les états avec des unions `freezed` (`Loading | Data | Error`), pas des champs nullables épars.
- **Pas de logique dans `build()`** : la logique vit dans le notifier/bloc ; le widget observe et affiche.
- **`select`/`watch` ciblés** pour limiter les rebuilds — ne pas écouter un objet entier pour un seul champ.
- **Disposer les ressources** : controllers, streams, focus nodes libérés dans `dispose()` (ou via `ref.onDispose`).
- **Pas de `setState` dans du code asynchrone sans garde `if (!mounted) return;`**.

---

## 6. Data fetching & couche réseau

- **Repository pattern** : la `presentation` n'appelle jamais `dio` directement.
- **Client réseau encapsulé** dans `core/network/` avec intercepteurs (auth, logging, retry).
- **Toute réponse externe désérialisée et validée** via les modèles `freezed`/`json_serializable` — ne jamais manipuler des `Map<String, dynamic>` bruts au-delà de la couche `data`.
- **Erreurs réseau typées** : convertir les exceptions `dio` en `Failure` du domaine (voir §8).
- **Pas de `Future` non attendu** (`unawaited()` explicite si volontaire).

---

## 7. Configuration & variables d'environnement

- **Flavors** (`dev`, `staging`, `prod`) via `--dart-define-from-file` ou des entrypoints dédiés (`main_dev.dart`, `main_prod.dart`).
- **Secrets injectés par `--dart-define`** au build — **jamais commités** dans le repo ni dans `pubspec.yaml`.
- **Aucune clé secrète dans le bundle** : tout ce qui est embarqué dans l'app est public (le binaire est décompilable). Les vrais secrets restent côté backend.
- **Configuration validée au démarrage** : l'app échoue tôt si une variable obligatoire manque.

---

## 8. Gestion des erreurs

- **Erreurs métier typées** : modéliser des `Failure` (`freezed`) plutôt que de propager des exceptions brutes à travers les couches.
- **Use cases retournent un résultat explicite** (`Either<Failure, T>` via `dartz`/`fpdart`, ou un `Result` `freezed`) plutôt que de `throw`.
- **UI** : tout état d'erreur a un rendu utilisateur (message + action de reprise). Pas d'erreur silencieuse.
- **`ErrorWidget.builder`** personnalisé en prod pour éviter l'écran rouge brut.
- **Capture globale** : `runZonedGuarded` + `FlutterError.onError` → remontée vers le monitoring (§11).

---

## 9. Performance

- **`const` partout où c'est possible** — évite les rebuilds inutiles.
- **`ListView.builder` / `GridView.builder`** pour les listes longues (lazy), jamais une `Column` géante dans un `SingleChildScrollView`.
- **Clés (`Key`)** pertinentes sur les listes réordonnables / éléments avec état.
- **Images** : `cached_network_image`, dimensions explicites, `cacheWidth`/`cacheHeight` pour redimensionner au décodage.
- **Découper les `build`** pour isoler les sous-arbres qui se reconstruisent.
- **Éviter le travail lourd sur l'UI thread** : `compute()` / isolates pour le parsing/calcul coûteux.
- **Profiler en mode `--profile`** (DevTools : timeline, rebuild counts) — pas en `debug` pour les mesures.

---

## 10. Sécurité

- **Aucun secret embarqué** (cf. §7) — l'app est décompilable.
- **Stockage sécurisé** des tokens via `flutter_secure_storage` (Keychain / Keystore), jamais `SharedPreferences` pour des données sensibles.
- **HTTPS uniquement** ; envisager le **certificate pinning** sur les endpoints sensibles.
- **Validation des entrées** côté app ET côté serveur (l'app ne fait jamais autorité).
- **Pas de log de données sensibles** (tokens, PII) — voir §11.
- **Obfuscation** au build release : `flutter build --obfuscate --split-debug-info=<dir>`.

---

## 11. Logging & monitoring

- **Pas de `print()` commité.** Utiliser un logger structuré (`logger` / `logging`) avec niveaux.
- **Niveaux** : `debug` (dev), `info` (événements métier), `warning`, `error`.
- **Jamais de PII ni de token en clair** dans les logs.
- **Monitoring crash & erreurs** : Sentry (`sentry_flutter`) ou Firebase Crashlytics — initialisé au bootstrap, capture via `runZonedGuarded`.
- **Symboles de debug uploadés** au monitoring sur chaque build release (stack traces lisibles malgré l'obfuscation).

---

## 12. Tests

### 12.1 Unitaires & domaine
- **`flutter_test`** pour la logique pure (use cases, notifiers, mappers). **Mocks via `mocktail`.**
- **Tester le comportement, pas l'implémentation.**

### 12.2 Widgets
- **`testWidgets`** pour les écrans et composants : interaction (`tester.tap`, `tester.enterText`), `pump`/`pumpAndSettle`, assertions via `find`.
- Tester les états : chargement, données, vide, erreur.

### 12.3 Intégration (e2e)
- **`integration_test`** pour les parcours critiques (login, parcours principal), lancés en CI sur device/émulateur.

### 12.4 Couverture
- Cible ≥ 70 % sur `domain/` et la logique d'état.
- Parcours critiques couverts en widget/integration.
- Pas de course à la couverture sur les widgets purement présentiels.

---

## 13. Formatage & qualité de code

- **`dart format .`** — non négociable, vérifié en CI (`dart format --set-exit-if-changed .`).
- **`flutter analyze`** : 0 warning/erreur. Lints stricts via `very_good_analysis` dans `analysis_options.yaml`.
- **Pas de `dynamic` implicite**, pas de `as` non sûr ; null-safety stricte.
- **`// ignore:` interdit sans justification** — corriger la cause, pas masquer le lint.
- **Génération de code** (`freezed`, `json_serializable`) via `dart run build_runner build --delete-conflicting-outputs` ; les fichiers `*.g.dart`/`*.freezed.dart` sont commités.
- **Commits** : Conventional Commits (`feat`, `fix`, `chore`…).

---

## 14. Accessibilité (a11y)

- **`Semantics`** sur les éléments interactifs non standard ; labels explicites sur les icônes cliquables.
- **Tailles tactiles ≥ 48×48 dp.**
- **Respecter le facteur d'échelle texte** (`MediaQuery.textScaler`) — pas de tailles figées qui cassent à 200 %.
- **Contraste WCAG AA** (4.5:1 pour le texte).
- **Navigation et focus** testés ; ordre de lecture logique pour les lecteurs d'écran (TalkBack/VoiceOver).

---

## 15. Internationalisation (si applicable)

- **`flutter_localizations` + `intl`** avec fichiers `.arb` — pas de chaînes en dur dans les widgets.
- **Formatage dates/nombres/devises** via `intl` (locale-aware).
- **Support RTL** vérifié si les locales le requièrent.

---

## 16. CI/CD

- **Pipeline minimum** : `flutter pub get → dart format --set-exit-if-changed . → flutter analyze → flutter test → flutter build`.
- **Génération de code** lancée avant l'analyse si nécessaire (`build_runner`).
- **Secrets** dans le secret store de la plateforme + `--dart-define` — jamais dans le repo.
- **Builds signés** (Android keystore / iOS provisioning) via la CI, secrets hors repo.

---

## 17. Checklist avant merge

- [ ] `dart format` appliqué, `flutter analyze` à 0 erreur
- [ ] Tests ajoutés/à jour, suite verte (`flutter test`)
- [ ] Pas de `print()`, pas de secret en dur, pas de PII en log
- [ ] Widgets `const` où possible, listes longues en `*.builder`
- [ ] Ressources libérées dans `dispose()` / `ref.onDispose`
- [ ] Données externes désérialisées via modèles typés, erreurs converties en `Failure`
- [ ] État géré avec le système retenu (pas de logique dans `build()`)
- [ ] Couleurs/typo via le thème, pas de valeurs en dur
- [ ] Fichiers générés (`*.g.dart`, `*.freezed.dart`) à jour et commités
- [ ] Accessibilité : tailles tactiles, contraste, échelle texte OK
