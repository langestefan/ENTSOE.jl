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
    // - `headingLevels: { h2: 4 }` — OAOperation labels its sub-sections
    //   (Authorizations / Parameters / Responses / Playground / Code
    //   Samples) with `<OAHeading level="h2">`, which by default emits
    //   `<h2>` and lands in VitePress's right-side TOC right next to the
    //   operation summary (also `<h2>`). The IDs are NOT operation-scoped
    //   either, so on a page with N operations the TOC fills with N x 5
    //   duplicate-anchor entries. Pushing those component headings to
    //   `<h4>` drops them from the outline (default range `[2, 3]`) while
    //   keeping every section — including the Playground / Try-it-out
    //   button — fully rendered.
    useTheme({
      headingLevels: { h2: 4 },
      operation: {
        cols: 1,
      },
    })
    openapiTheme.enhanceApp({ app })
  },
}
export default Theme
