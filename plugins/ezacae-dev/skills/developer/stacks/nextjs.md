# Conventions de stack — Next.js (App Router)

> **Bibliothèque de conventions du skill `developer` — entrée `nextjs`.** Chargé automatiquement quand la détection de stack identifie un projet Next.js. Contient les conventions **génériques** Next.js / React / TypeScript valables pour toute application ezacae sur cette stack.
>
> **Spécificités d'une application donnée** (catalogue de hooks/composants maison, modèle Firestore/SQL propre au projet, palette de couleurs, intégrations) **ne sont pas ici** : elles vivent dans le `CLAUDE.md` à la racine du repo applicatif, chargé en complément. En cas de conflit, **le `CLAUDE.md` du projet prime**.
>
> Commandes de vérification de cette stack : `lint`, `typecheck`, `test`, `build` via le gestionnaire de paquets détecté (`pnpm` si `pnpm-lock.yaml`, sinon `npm`).

---

## 1. Stack & versions

- **Framework** : Next.js (≥ 15, App Router exclusivement)
- **React** : ≥ 19 (Server Components, Server Actions)
- **Langage** : TypeScript en mode `strict`
- **Package manager** : `pnpm` (privilégié) ou `npm`
- **Styling** : Tailwind CSS (+ shadcn/ui pour le design system)
- **Validation** : `zod` (schémas partagés client/serveur)
- **Data fetching client** : TanStack Query (si nécessaire — préférer Server Components)
- **Formulaires** : `react-hook-form` + `zod`
- **Tests** : Vitest (unitaires) + Playwright (e2e)
- **Lint/format** : ESLint (`eslint-config-next`) + Prettier

---

## 2. Architecture & organisation du code

### 2.1 Structure recommandée (App Router)

```
src/
├── app/                          # Router : pages, layouts, API routes
│   ├── (marketing)/              # Route group, pas d'impact URL
│   │   └── page.tsx
│   ├── (app)/                    # Routes authentifiées
│   │   ├── layout.tsx
│   │   └── dashboard/
│   │       ├── page.tsx
│   │       ├── loading.tsx
│   │       └── error.tsx
│   ├── api/                      # Route Handlers
│   │   └── webhooks/
│   │       └── route.ts
│   ├── layout.tsx                # Root layout
│   ├── error.tsx                 # Error boundary global
│   ├── not-found.tsx
│   └── globals.css
├── components/                   # Composants réutilisables
│   ├── ui/                       # Composants de base (shadcn/ui)
│   └── features/                 # Composants métier
│       └── users/
│           ├── user-card.tsx
│           └── user-form.tsx
├── lib/                          # Logique partagée non-UI
│   ├── api/                      # Clients d'API typés
│   ├── auth/
│   ├── db/
│   ├── logger.ts
│   ├── env.ts                    # Validation des env vars
│   └── utils.ts
├── hooks/                        # Hooks React custom
├── schemas/                      # Schémas zod partagés
├── types/                        # Types TypeScript partagés
└── styles/
```

### 2.2 Règles structurelles

- **Découpage par feature, pas par type de fichier** (sauf `components/ui` et `lib/`).
- **Server Components par défaut.** Marquer `'use client'` uniquement quand c'est nécessaire (interactivité, hooks, state local, événements).
- **Pousser `'use client'` aussi bas que possible** dans l'arbre des composants — un composant client peut recevoir des Server Components en `children`.
- **Pas de logique métier dans les composants** — extraire dans `lib/` ou des hooks.
- **Pas de logique métier dans les pages** — la page orchestre, les composants affichent, `lib/` calcule.
- **Pas de fetch dans `useEffect`** côté serveur disponible — utiliser Server Components ou Server Actions.

### 2.3 Server vs Client Components

| Use case | Server Component | Client Component |
|---|---|---|
| Affichage de données BDD | ✅ | ❌ |
| Accès à des secrets / API privées | ✅ | ❌ |
| `useState`, `useEffect`, `useRef` | ❌ | ✅ |
| `onClick`, `onChange`, formulaires interactifs | ❌ | ✅ |
| `localStorage`, `window`, `document` | ❌ | ✅ |
| Composants lourds bibliothèques tierces UI | ❌ | ✅ |

---

## 3. Nommage

### 3.1 Conventions

| Élément | Convention | Exemple |
|---|---|---|
| Fichier composant | `kebab-case.tsx` | `user-card.tsx` |
| Composant React | `PascalCase` | `UserCard` |
| Fichier route Next.js | réservé (`page.tsx`, `layout.tsx`, `loading.tsx`, `error.tsx`, `route.ts`) | — |
| Variable / fonction | `camelCase` | `getUserById` |
| Hook | `use<Name>` en `camelCase` | `useDebouncedValue` |
| Constante | `UPPER_SNAKE_CASE` | `DEFAULT_PAGE_SIZE` |
| Type / Interface | `PascalCase` (pas de préfixe `I`) | `User`, `UserCardProps` |
| Variable d'env publique | `NEXT_PUBLIC_*` | `NEXT_PUBLIC_API_URL` |
| Variable d'env privée | `UPPER_SNAKE_CASE` | `DATABASE_URL` |

### 3.2 Sémantique

- Composants nommés par ce qu'ils sont (`UserCard`), pas par ce qu'ils utilisent (`UserDiv`).
- Props booléennes : `isLoading`, `hasError`, `canEdit`.
- Handlers : `handle<Event>` à l'intérieur, `on<Event>` en prop : `<Button onClick={handleClick} />`.
- Pas d'abréviations sauf universelles (`id`, `url`, `http`).

---

## 4. Mutualisation & homogénéité

### 4.1 Composants UI

- **`components/ui/`** : composants atomiques sans logique métier (Button, Input, Card). Idéalement issus de shadcn/ui pour ne pas réinventer la roue.
- **`components/features/<feature>/`** : composants liés à une fonctionnalité.
- **Un composant fait UNE chose.** S'il dépasse 200 lignes, le découper.
- **Props typées explicitement** — pas de `any`, pas de `React.FC` (préférer le typage direct du paramètre).

```tsx
type UserCardProps = {
  user: User;
  onEdit?: (userId: string) => void;
};

export function UserCard({ user, onEdit }: UserCardProps) { … }
```

### 4.2 Logique partagée

- **`lib/`** : code partagé sans dépendance React.
- **`hooks/`** : hooks réutilisables (`useDebouncedValue`, `useMediaQuery`, `useLocalStorage`).
- **`schemas/`** : schémas zod partagés entre client (form) et serveur (API/Server Action) — single source of truth.
- **Types dérivés des schémas** : `type User = z.infer<typeof userSchema>`.

### 4.3 Design system & styling

- **Tailwind CSS uniquement** — pas de CSS-in-JS sauf cas exceptionnel justifié.
- **Tokens centralisés** dans `tailwind.config.ts` (couleurs, spacing, typo).
- **Pas de styles inline** sauf valeurs dynamiques calculées.
- **Utiliser `cn()`** (helper `clsx` + `tailwind-merge`) pour combiner les classes conditionnelles.
- **Composants accessibles par défaut** : Radix UI primitives sous shadcn/ui — respecter les rôles ARIA.

---

## 5. Data fetching

### 5.1 Côté serveur (priorité)

- **`fetch` dans les Server Components** avec options de cache Next.js explicites :
  ```tsx
  await fetch(url, { next: { revalidate: 60 } });  // ISR
  await fetch(url, { cache: 'no-store' });          // Dynamique
  ```
- **Server Actions** pour les mutations — typage bout en bout, validation zod en entrée.
- **Pas de fetch d'API privée depuis le client** sauf via une Server Action ou un Route Handler.

### 5.2 Côté client (si nécessaire)

- **TanStack Query** pour les états serveur côté client (cache, retry, invalidation).
- **Pas de `useEffect` + `fetch`** dans 99 % des cas — soit Server Component, soit TanStack Query.

### 5.3 Validation des données externes

- **Toute donnée venant de l'extérieur (API, formulaire, URL) est validée par zod** avant utilisation.
- Ne jamais faire confiance à un type TS sur une donnée d'origine externe.

---

## 6. Variables d'environnement

- **Validation stricte au boot** via `@t3-oss/env-nextjs` ou un schéma zod custom dans `lib/env.ts`.
- L'app refuse de démarrer si une variable obligatoire manque.
- **`NEXT_PUBLIC_*`** uniquement pour les variables exposées au navigateur (URL d'API publique, clé Stripe publique, etc.).
- **JAMAIS de secret en `NEXT_PUBLIC_*`** — exposé dans le bundle client.
- **`.env.example`** à jour, `.env.local` dans `.gitignore`.

```typescript
// lib/env.ts
import { createEnv } from '@t3-oss/env-nextjs';
import { z } from 'zod';

export const env = createEnv({
  server: { DATABASE_URL: z.string().url() },
  client: { NEXT_PUBLIC_API_URL: z.string().url() },
  runtimeEnv: {
    DATABASE_URL: process.env.DATABASE_URL,
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
  },
});
```

---

## 7. Logging

### 7.1 Principes

- **Pas de `console.log` en code de production.** Acceptable ponctuellement en dev, jamais commité.
- **Logger structuré JSON côté serveur** : `pino` (lightweight, perf).
- **Côté client** : minimum. Logs d'erreur seulement, envoyés à Sentry/LogRocket.

### 7.2 Implémentation

```typescript
// lib/logger.ts
import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  redact: ['*.password', '*.token', 'req.headers.authorization'],
});
```

### 7.3 Règles

- **Toujours du contexte** : `logger.info({ userId, action }, 'user logged in')`.
- **Erreurs avec leur cause** : `logger.error({ err }, 'failed to fetch user')`.
- **Niveaux** : `debug` (dev), `info` (événements métier), `warn`, `error`, `fatal`.
- **Jamais de PII en clair dans les logs** : pas d'e-mail entier, pas de mot de passe, pas de token.
- **Redact pino** obligatoire sur tous les champs sensibles.

---

## 8. Gestion des erreurs

### 8.1 UI

- **`error.tsx`** à chaque niveau de segment où on veut un boundary dédié.
- **`not-found.tsx`** pour les 404 sémantiques (appelée via `notFound()`).
- **`loading.tsx`** pour les états de chargement (Suspense automatique).
- **Pas d'erreur silencieuse** : toute erreur catch logue + remonte un retour utilisateur ou un Sentry.

### 8.2 Server Actions

- **Retour typé `{ success: true, data } | { success: false, error }`** plutôt que `throw`.
- **Validation zod en première ligne** de chaque Server Action.
- **Logger les erreurs serveur** avec contexte utilisateur (sans PII sensible).

### 8.3 Réseau

- **TanStack Query** : configurer `retry`, `staleTime`, `gcTime` selon le besoin.
- **Pas de promesses non gérées** — toujours `await` ou `.catch`.

---

## 9. Performance

### 9.1 Rendu

- **Server Components par défaut** — réduit drastiquement le JS envoyé au client.
- **`<Image />` de Next.js** pour toutes les images — `width`/`height` obligatoires.
- **`<Link>` de Next.js** pour la navigation interne — préfetch automatique.
- **`next/font`** pour les polices (zero CLS, self-hosting auto).
- **Streaming** via Suspense pour les sections lentes.

### 9.2 Bundle

- **Analyser le bundle** : `@next/bundle-analyzer` régulièrement.
- **`dynamic()` import** pour les composants client lourds non critiques au-dessus de la ligne de flottaison.
- **Éviter les libs lourdes côté client** (moment.js, lodash entier). Préférer `date-fns`, ou des imports ciblés.
- **Tree-shaking vérifié** sur les libs ajoutées.

### 9.3 Core Web Vitals

- **LCP** < 2,5 s : optimiser images, fonts, server response.
- **INP** < 200 ms : éviter le JS bloquant, hydrater progressivement.
- **CLS** < 0,1 : dimensions explicites sur images/vidéos, pas de contenu injecté qui décale la mise en page.
- Mesurer en continu via Vercel Analytics ou équivalent.

### 9.4 Cache

- **`revalidate`** et **`unstable_cache`** pour les données semi-statiques.
- **`revalidateTag` / `revalidatePath`** après mutation côté Server Action.

---

## 10. Sécurité

- **Pas de secret en `NEXT_PUBLIC_*`.**
- **Middleware** (`middleware.ts`) pour les vérifications d'auth amont (redirection si non connecté).
- **Validation zod** systématique sur toutes les Server Actions et Route Handlers.
- **CSRF** : Server Actions de Next.js inclut une protection ; sur les Route Handlers exposés, vérifier l'origine.
- **Headers de sécurité** : configurer `Content-Security-Policy`, `Strict-Transport-Security`, `X-Frame-Options` dans `next.config.ts` ou via middleware.
- **Rate limiting** sur les endpoints sensibles (login, signup) — Upstash Ratelimit ou middleware custom.
- **Sanitization des inputs HTML** : `DOMPurify` si on rend du HTML utilisateur (à éviter au maximum).
- **Pas de `dangerouslySetInnerHTML`** sauf cas exceptionnel justifié et sanitizé.

---

## 11. Tests

### 11.1 Unitaires

- **Vitest** + **React Testing Library** pour les composants.
- **Tester le comportement, pas l'implémentation** : ce que l'utilisateur voit/fait, pas les détails internes.
- **Hooks custom testés isolément** via `renderHook`.

### 11.2 E2E

- **Playwright** pour les parcours critiques (login, inscription, parcours d'achat).
- Tests E2E lancés en CI sur une build de prévisualisation.

### 11.3 Couverture cible

- ≥ 70 % sur `lib/` et `hooks/`
- Parcours critiques couverts E2E
- Pas de course à la couverture sur les composants triviaux

---

## 12. Monitoring & observabilité

- **Sentry** pour le tracking d'erreurs (client + serveur) — wizard officiel : `npx @sentry/wizard@latest -i nextjs`.
- **Vercel Analytics** + **Speed Insights** si déployé sur Vercel.
- **OpenTelemetry** côté serveur si besoin de tracing distribué avec le backend.
- **Source maps uploadées** à Sentry sur chaque build pour des stacks lisibles.
- **Dashboards** : taux d'erreur, latence, Core Web Vitals, taux de conversion des parcours clés.

---

## 13. Formatage & qualité de code

### 13.1 Outils

- **Prettier** : config versionnée. **Formater uniquement les fichiers de la tâche** (`pnpm/npm run format -- <fichiers>`), ou vérifier avec `format:check`. ⚠️ Ne **jamais** lancer `format` / `prettier --write` **sans cible** : cela reformate tout le dépôt et pollue le diff avec des dizaines de fichiers non liés (surtout en worktree partagé).
- **ESLint** avec `eslint-config-next` + `@typescript-eslint`.
- **Husky + lint-staged** : lint + format auto sur `pre-commit`.
- **Commitlint** : Conventional Commits (`feat`, `fix`, `chore`, etc.).
- **TypeScript strict** non négociable.

### 13.2 Règles TypeScript

```json
{
  "strict": true,
  "noUncheckedIndexedAccess": true,
  "noUnusedLocals": true,
  "noUnusedParameters": true
}
```

- **Pas de `any`.** `unknown` puis narrowing.
- **Pas de `@ts-ignore`** sans commentaire explicatif ; préférer `@ts-expect-error`.
- **Imports absolus** via `@/...` (configuré dans `tsconfig.json`).

### 13.3 Conventions React

- **Composants en `function`** déclarés (`export function Foo() {…}`), pas en arrow exportée — meilleur stack trace, hoisting.
- **Props destructurées dans la signature** : `function Foo({ a, b }: Props)`.
- **`children: React.ReactNode`** quand on accepte des enfants.
- **Pas de logique dans le JSX** — extraire dans des variables/composants.

---

## 14. Accessibilité (a11y)

- **HTML sémantique** : `<button>` pour les actions, `<a>` pour la navigation, jamais l'inverse.
- **Alt text** obligatoire sur les images informatives ; `alt=""` sur les décoratives.
- **Focus visible** : ne jamais désactiver `outline` sans alternative claire.
- **Navigation au clavier** testée sur les parcours principaux.
- **ARIA** quand le sémantique HTML ne suffit pas — pas en plus, jamais en remplacement.
- **Contraste WCAG AA minimum** (4.5:1 pour le texte).
- **`lighthouse`** et **`axe`** lancés régulièrement (idéalement en CI).

---

## 15. Internationalisation (si applicable)

- **`next-intl`** ou équivalent pour les apps multilingues.
- **Pas de chaînes en dur** dans le JSX — toutes via fichiers de traduction.
- **Formatage de dates/nombres** via `Intl.*` (locale-aware).

---

## 16. CI/CD

- **Pipeline minimum** : `install → lint → typecheck → test → build`.
- **Preview deployments** sur chaque PR (Vercel ou équivalent).
- **Secrets** dans le secret store de la plateforme — pas dans le repo.
- **Lighthouse CI** sur les pages clés (optionnel mais recommandé).

---

## 17. Checklist avant merge

- [ ] Code formaté (`pnpm format`) et lint passant (`pnpm lint`)
- [ ] Typecheck OK (`pnpm typecheck`)
- [ ] Tests ajoutés/à jour, suite verte
- [ ] Pas de `console.log`, pas de `any` non justifié, pas de secret en dur
- [ ] `'use client'` placé au plus bas niveau possible
- [ ] Données externes validées par zod
- [ ] Images via `<Image />`, liens via `<Link>`, polices via `next/font`
- [ ] Accessibilité : navigation clavier OK, contraste OK, alt text présent
- [ ] Variables d'env ajoutées à `.env.example` et au schéma
- [ ] Pas de régression Core Web Vitals (LCP, INP, CLS)
