import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Set `site` and `base` so the deployed URL works under GitHub Pages.
// Override via env when self-hosting on a custom domain.
const site = process.env.DOCS_SITE_URL ?? 'https://silfaran.github.io';
const base = process.env.DOCS_BASE_PATH ?? '/ai-standards';

export default defineConfig({
  site,
  base,
  markdown: {
    syntaxHighlight: 'shiki',
    // Mermaid diagrams render client-side via a small inline script
    // injected by Starlight's `head` config below — see the customCss /
    // head section. We avoid `rehype-mermaid` because it transitively
    // pulls in playwright (~200MB) for build-time SVG rendering, which
    // is overkill for a docs site. The `language-mermaid` code blocks
    // are picked up by mermaid.js on the client.
  },
  integrations: [
    starlight({
      title: 'ai-standards',
      description:
        'A Claude Code orchestration framework that builds full-stack applications via isolated AI agents — spec, implement, review, and test each feature against enforced architectural standards.',
      social: {
        github: 'https://github.com/Silfaran/ai-standards',
      },
      editLink: {
        baseUrl: 'https://github.com/Silfaran/ai-standards/edit/master/docs/',
      },
      // i18n is intentionally not configured today (English-only). When adding
      // a second language, swap defaultLocale to a locale code and add a
      // `locales` map. Starlight handles the rest natively.
      sidebar: [
        {
          label: 'Get started',
          items: [
            { slug: 'index' },
            { slug: 'guides/quickstart' },
            { slug: 'guides/your-first-feature' },
          ],
        },
        {
          label: 'Concepts',
          items: [
            { slug: 'concepts/pipeline' },
            { slug: 'concepts/standards-and-critical-paths' },
            { slug: 'concepts/per-phase-bundles' },
            { slug: 'concepts/coverage-aware-loading' },
            { slug: 'concepts/status-block-contract' },
            { slug: 'concepts/test-ownership' },
            { slug: 'concepts/token-economics' },
          ],
        },
        {
          label: 'Reference',
          items: [
            {
              label: 'Agents',
              autogenerate: { directory: 'reference/agents' },
            },
            {
              label: 'Commands',
              autogenerate: { directory: 'reference/commands' },
            },
            {
              label: 'Critical paths',
              autogenerate: { directory: 'reference/critical-paths' },
            },
            { slug: 'reference/skills' },
            { slug: 'reference/rule-id-prefixes' },
            { slug: 'reference/smoke-checks' },
          ],
        },
        {
          label: 'Project',
          items: [
            { slug: 'project/architecture' },
            { slug: 'project/usage' },
            { slug: 'project/changelog' },
          ],
        },
      ],
      lastUpdated: true,
      pagination: true,
      // Inject the Mermaid runtime so `language-mermaid` code blocks render
      // as diagrams. The script tag lives in <head>; the inline module finds
      // every <pre><code class="language-mermaid"> on the page, replaces it
      // with a <pre class="mermaid"> element, and tells mermaid to render.
      head: [
        {
          tag: 'script',
          attrs: { type: 'module' },
          content: `
            import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

            function transformMermaidBlocks() {
              document.querySelectorAll('pre > code.language-mermaid').forEach((codeEl) => {
                const pre = codeEl.parentElement;
                if (!pre || pre.dataset.mermaidProcessed) return;
                const wrap = document.createElement('pre');
                wrap.className = 'mermaid';
                wrap.textContent = codeEl.textContent ?? '';
                pre.replaceWith(wrap);
              });
            }

            function applyTheme() {
              const theme = document.documentElement.dataset.theme === 'dark' ? 'dark' : 'default';
              mermaid.initialize({ startOnLoad: false, theme, securityLevel: 'strict' });
            }

            function render() {
              transformMermaidBlocks();
              applyTheme();
              mermaid.run({ querySelector: '.mermaid' });
            }

            // Initial render after DOM ready.
            if (document.readyState === 'loading') {
              document.addEventListener('DOMContentLoaded', render);
            } else {
              render();
            }

            // Re-render on Starlight's client-side route changes.
            document.addEventListener('astro:page-load', render);

            // Re-theme when the user toggles the theme switcher.
            new MutationObserver(() => render()).observe(document.documentElement, {
              attributes: true,
              attributeFilter: ['data-theme'],
            });
          `,
        },
      ],
    }),
  ],
});
