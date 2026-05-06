// .vitepress/theme/index.ts — extends DocumenterVitepress's default theme and
// registers `vitepress-openapi` so the `<OASpec />` component used in
// docs/src/api/index.md can mount.
import { h } from 'vue'
import DefaultTheme from 'vitepress/theme'
import type { Theme as ThemeConfig } from 'vitepress'
import 'virtual:mathjax-styles.css'

import {
  NolebaseEnhancedReadabilitiesMenu,
  NolebaseEnhancedReadabilitiesScreenMenu,
} from '@nolebase/vitepress-plugin-enhanced-readabilities/client'

import VersionPicker from '@/VersionPicker.vue'
import AuthorBadge from '@/AuthorBadge.vue'
import Authors from '@/Authors.vue'
import SidebarDrawerToggle from '@/SidebarDrawerToggle.vue'

import { enhanceAppWithTabs } from 'vitepress-plugin-tabs/client'
import { theme as openapiTheme, useOpenapi, useTheme } from 'vitepress-openapi/client'
import 'vitepress-openapi/dist/style.css'
import spec from '../../public/openapi.json'

import '@nolebase/vitepress-plugin-enhanced-readabilities/client/style.css'
import './style.css'
import './docstrings.css'

export const Theme: ThemeConfig = {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'nav-bar-content-after': () => [h(NolebaseEnhancedReadabilitiesMenu)],
      'nav-screen-content-after': () => h(NolebaseEnhancedReadabilitiesScreenMenu),
      'nav-bar-content-before': () => h(SidebarDrawerToggle),
    })
  },
  enhanceApp({ app, router, siteData }) {
    enhanceAppWithTabs(app)
    app.component('VersionPicker', VersionPicker)
    app.component('AuthorBadge', AuthorBadge)
    app.component('Authors', Authors)
    useOpenapi({ spec })
    // Configure how each `<OAOperation>` renders.
    //
    // - `cols: 1` — single-column layout reads better on doc sites; the
    //   default two-column mode crams the playground next to the schema.
    // - `headingLevels` —
    //   * `h2: 3` shifts OAOperation's sub-section labels (Authorizations
    //     / Parameters / Responses / Playground / Code Samples), which
    //     are emitted via `<OAHeading level="h2">`, to render as `<h3>`
    //     instead. They then nest under the operation summary `<h2>`
    //     (from our markdown) in VitePress's right-side TOC.
    //   * `h1: 4` shifts the OAOperation `header` slot's title (emitted
    //     via `<OAHeading level="h1">`) from `<h1>` to `<h4>`. Two
    //     reasons: (1) it visually duplicates our `## summary` markdown
    //     heading; (2) sitting between our `<h2>` and the sub-section
    //     `<h3>`s as an `<h1>`, it makes VitePress's outline scanner
    //     treat the `<h1>` as a hierarchy reset, so the `<h3>` entries
    //     end up as siblings of the `<h2>` instead of children. Pushing
    //     it to `<h4>` removes both problems.
    //   Pair this with `prefix-headings="true"` on each `<OAOperation>`
    //   invocation in `make.jl` so the per-section anchor IDs are
    //   operation-scoped (`<operationId>-authorizations`) and the inner
    //   TOC links resolve to the right operation.
    useTheme({
      headingLevels: { h1: 4, h2: 3 },
      operation: {
        cols: 1,
      },
    })
    openapiTheme.enhanceApp({ app })
  },
}
export default Theme
