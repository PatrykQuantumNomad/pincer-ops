# Astro + GitHub Pages Research for Pincer Ops Landing Page

## 1. Astro Project Setup

### Current Version
- **Astro 5.17.3** (latest stable as of Feb 2026)
- **create-astro 4.12.1** (scaffolding CLI)

### Scaffolding in a Monorepo Subdirectory

Since pincer-ops is an existing monorepo, the Astro site should live in a subdirectory (recommended: `/site`). Scaffold with:

```bash
# From repo root
npm create astro@latest -- --template minimal site/

# Or with a starter template
npm create astro@latest -- --template basics site/
```

This creates a self-contained Astro project with its own `package.json` at `site/`. The monorepo root does NOT need to be an npm workspace unless you want shared dependencies.

### Recommended `site/astro.config.mjs`

```js
import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind'; // deprecated - use Tailwind v4 Vite plugin instead
import react from '@astrojs/react';

export default defineConfig({
  site: 'https://pincer.patrykgolabek.dev',
  // No 'base' needed with a custom domain (no path prefix)
  integrations: [
    react(),   // For React islands (Framer Motion, interactive components)
  ],
  vite: {
    css: {
      // Tailwind v4 is configured via Vite plugin, not @astrojs/tailwind
    },
  },
});
```

### Tailwind v4 Setup (Current Best Practice)

The `@astrojs/tailwind` integration is **deprecated** as of Astro 5.2+. Use the native Tailwind v4 Vite plugin instead:

```bash
cd site/
npx astro add tailwind   # Automatically installs Tailwind v4 Vite plugin
```

Or manually:

```bash
npm install tailwindcss @tailwindcss/vite
```

Then in `astro.config.mjs`:

```js
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  vite: {
    plugins: [tailwindcss()],
  },
});
```

And in your main CSS file:

```css
@import 'tailwindcss';
```

---

## 2. GitHub Actions Deployment Workflow

### Official Workflow (using `withastro/action@v5`)

Create at `.github/workflows/deploy-site.yml`:

```yaml
name: Deploy Landing Page to GitHub Pages

on:
  push:
    branches: [main]
    paths:
      - 'site/**'          # Only trigger on site changes
  workflow_dispatch:        # Manual trigger

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v5

      - name: Install, build, and upload site
        uses: withastro/action@v5
        with:
          path: ./site      # Subdirectory containing the Astro project

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

### Key Configuration Notes

| Parameter | Value | Notes |
|-----------|-------|-------|
| `path` | `./site` | Points to the Astro project subdirectory |
| `node-version` | `22` (default) | Override with `node-version: 24` if needed |
| `package-manager` | Auto-detected | From lockfile (npm/pnpm/yarn/bun/deno) |
| `cache` | `true` (default) | Caches optimized images and assets |
| `build-cmd` | Auto | Runs `<pkg-manager> run build` |

### GitHub Settings Required

1. Go to **Settings > Pages** in the repo
2. Under "Build and deployment", set Source to **"GitHub Actions"**
3. The workflow handles the rest

### Coexistence with Existing CI

The existing `.github/workflows/validate-manifests.yml` runs on PRs to main. The new deploy workflow only triggers on pushes to main AND only when `site/**` changes, so there is no conflict.

---

## 3. Custom Domain Configuration (pincer.patrykgolabek.dev)

### Step 1: CNAME File

Create `site/public/CNAME` containing:

```
pincer.patrykgolabek.dev
```

This file gets deployed to the root of the GitHub Pages site and tells GitHub to serve the site on the custom domain.

### Step 2: DNS Configuration

Since `pincer.patrykgolabek.dev` is a **subdomain** (not an apex domain), configure a **CNAME record** at your DNS provider:

| Type | Name | Value |
|------|------|-------|
| `CNAME` | `pincer` | `OpenClaw.github.io` (or `<username>.github.io` depending on the org/user that owns the repo) |

**Note:** Adjust the CNAME target to match the actual GitHub org/user that hosts the pincer-ops repo.

### Step 3: GitHub Repository Settings

1. Go to **Settings > Pages > Custom domain**
2. Enter `pincer.patrykgolabek.dev`
3. Click Save
4. Enable **"Enforce HTTPS"** (automatic with GitHub's Let's Encrypt integration)

### DNS Propagation

- CNAME changes typically propagate within minutes to a few hours
- GitHub's HTTPS certificate provisioning can take up to 24 hours after DNS verification

### If the Apex Domain (patrykgolabek.dev) is Also Needed

Configure A records pointing to GitHub Pages IPs:

```
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

And AAAA records for IPv6:

```
2606:50c0:8000::153
2606:50c0:8001::153
2606:50c0:8002::153
2606:50c0:8003::153
```

---

## 4. Recommended Astro Integrations

### Core Integrations

| Integration | Purpose | Install |
|-------------|---------|---------|
| `@astrojs/react` | React islands for interactive components | `npx astro add react` |
| `@tailwindcss/vite` | Tailwind CSS v4 (via Vite plugin) | `npm install tailwindcss @tailwindcss/vite` |
| `@astrojs/mdx` | MDX content support | `npx astro add mdx` |
| `@astrojs/sitemap` | Auto-generate sitemap.xml | `npx astro add sitemap` |

### Animation Libraries (for fun, creative design)

| Library | Best For | How to Use in Astro |
|---------|----------|---------------------|
| **Motion (Framer Motion)** | React component animations, gestures, layout animations | Use inside React islands with `client:visible` or `client:idle` |
| **GSAP** | Timeline-based animations, scroll triggers, text effects | `<script>` tags in Astro components or client-side scripts |
| **Three.js** | 3D WebGL scenes, particle effects, backgrounds | React Three Fiber in React islands or vanilla in `<script>` |
| **anime.js** | Lightweight DOM animations, SVG morphing | Direct `<script>` tag usage |
| **Lottie** | Pre-made vector animations (from After Effects) | `lottie-web` in `<script>` or React wrapper |

### Recommended Approach for This Project

**Primary:** GSAP for scroll-driven animations + Tailwind for styling
**Secondary:** Three.js (via React Three Fiber) for a hero 3D element if desired
**Fallback:** CSS animations + Astro View Transitions for lightweight interactivity

GSAP is the strongest choice because:
- Works perfectly in plain `<script>` tags (no React island needed)
- ScrollTrigger plugin enables scroll-driven animations
- No hydration cost for most animations
- Proven combination with Astro (Codrops tutorial from Feb 2026 demonstrates GSAP + Three.js + Astro)

---

## 5. Astro Features for Fun Designs

### View Transitions API

Astro has built-in support for the browser View Transitions API, enabling SPA-like page transitions in a multi-page static site.

```astro
---
// src/layouts/Layout.astro
import { ViewTransitions } from 'astro:transitions';
---
<html>
  <head>
    <ViewTransitions />
  </head>
  <body>
    <slot />
  </body>
</html>
```

Key directives:
- `transition:animate="slide"` - Slide transitions between pages
- `transition:animate="fade"` - Fade transitions
- `transition:persist` - Persist component state across navigations (great for music players, 3D scenes)
- Custom animation definitions for unique effects

**Browser support:** 85%+ (Chrome 126+, Firefox 144+). Astro gracefully falls back to normal navigation in unsupported browsers.

### Islands Architecture

Astro's killer feature for performance + interactivity:

```astro
---
import InteractiveHero from '../components/InteractiveHero.tsx';
import StaticContent from '../components/StaticContent.astro';
---

<!-- Zero JS - renders to static HTML -->
<StaticContent />

<!-- React island - hydrates only when visible in viewport -->
<InteractiveHero client:visible />
```

Client directives for controlling hydration:
- `client:load` - Hydrate immediately on page load
- `client:idle` - Hydrate when browser is idle
- `client:visible` - Hydrate when element enters viewport (best for below-fold content)
- `client:media="(max-width: 768px)"` - Hydrate based on media query
- `client:only="react"` - Skip SSR, render only on client (for WebGL/canvas)

### Content Collections

Type-safe content management for blog posts, project showcases, etc.:

```ts
// src/content/config.ts
import { defineCollection, z } from 'astro:content';

const features = defineCollection({
  schema: z.object({
    title: z.string(),
    description: z.string(),
    icon: z.string(),
    order: z.number(),
  }),
});

export const collections = { features };
```

---

## 6. Notable Astro Themes and Templates

### Best Fits for a DevOps/Tech Landing Page

| Theme | Style | Why It Fits |
|-------|-------|-------------|
| **[Brutal](https://astro.build/themes/details/brutal/)** | Neobrutalist, bold, high-contrast | Fun, edgy aesthetic that stands out. Minimal yet impactful. Great for a DevOps tool. |
| **[AstroWind](https://github.com/arthelokyo/astrowind)** | Clean, modern, Tailwind-based | Astro 5 + Tailwind, perfect PageSpeed scores, good landing page structure |
| **[Astro Landing Page](https://astro.build/themes/details/astro-landing-page/)** | SaaS/startup landing | Clean sections, CTAs, feature grids. Good structural reference. |
| **[astro-landing-template](https://github.com/rafpiek/astro-landing-template)** | Linear/Notion/Tesla-inspired | Performance-optimized, React + Tailwind, modern design principles |
| **[Starlight](https://starlight.astro.build/)** | Documentation | If docs are needed alongside the landing page (could be a separate section) |

### Recommendation

Do NOT use a theme as-is. Instead:
1. Start from `npm create astro@latest -- --template minimal` for full control
2. Reference **Brutal** for visual inspiration (bold, techy aesthetic)
3. Reference **astro-landing-template** for component structure (hero, features, CTA sections)
4. Build custom with Tailwind v4 + GSAP animations

---

## 7. CSS Animation Libraries Compatibility with Astro

### Tier 1: Best Compatibility

| Library | Size | Astro Integration | Notes |
|---------|------|-------------------|-------|
| **GSAP 3.x** | ~30KB core | Direct `<script>` in `.astro` files | ScrollTrigger, TextPlugin, SplitText. Free for most uses. No React needed. |
| **CSS Animations** | 0KB | Native | Tailwind's built-in animations + `@keyframes`. Zero JS overhead. |

### Tier 2: Great with React Islands

| Library | Size | Astro Integration | Notes |
|---------|------|-------------------|-------|
| **Motion (Framer Motion)** | ~30KB | React island with `client:visible` | Best-in-class React animation. Layout animations, gestures, AnimatePresence. |
| **React Spring** | ~20KB | React island | Physics-based animations. Good for natural-feeling motion. |

### Tier 3: Specialized (Use Sparingly)

| Library | Size | Astro Integration | Notes |
|---------|------|-------------------|-------|
| **Three.js** | ~150KB | React Three Fiber in `client:only="react"` island | 3D scenes, particle systems. Use for ONE hero element, not site-wide. |
| **anime.js** | ~17KB | Direct `<script>` | Lightweight alternative to GSAP. Good for SVG morphing. |
| **Lottie** | ~50KB | `<script>` or React wrapper | Vector animations from After Effects. Good for icons/illustrations. |

### Performance Strategy

For a landing page that should load fast:

1. **Above the fold:** CSS animations only (Tailwind utilities, `@keyframes`)
2. **On scroll:** GSAP ScrollTrigger (loaded async, small footprint)
3. **Interactive sections:** React islands with Motion, hydrated `client:visible`
4. **3D hero (optional):** Three.js in a single `client:only="react"` island

This approach keeps initial JS payload under 50KB while enabling rich interactivity.

---

## Summary of Recommendations

1. **Scaffold** with `npm create astro@latest -- --template minimal site/`
2. **Tailwind v4** via `@tailwindcss/vite` plugin (not the deprecated `@astrojs/tailwind`)
3. **React integration** for interactive islands (Motion/Framer Motion, optional Three.js)
4. **GSAP** for scroll-driven animations in plain `<script>` tags (no hydration cost)
5. **View Transitions** for smooth page navigation (built into Astro)
6. **GitHub Actions** with `withastro/action@v5` and `path: ./site`
7. **Custom domain** via CNAME record + `public/CNAME` file
8. **No theme** - build custom from minimal template for full creative control
9. **Neobrutalist/bold aesthetic** inspired by Brutal theme for a DevOps-appropriate vibe
10. **Progressive enhancement** - CSS first, GSAP on scroll, React islands for interactivity
