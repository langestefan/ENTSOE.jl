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
    // - `hiddenSlots` — drop the per-operation sub-sections (Authorizations
    //   / Parameters / Responses / Playground / Samples). vitepress-openapi
    //   renders their headings at the same level as the operation summary
    //   (`<h2>`) and does NOT operation-scope the heading IDs, so on a tag
    //   page with N operations the right-side TOC ends up with N x 5
    //   duplicate-anchor entries. Hiding the slots is the cleanest fix
    //   until upstream operation-scopes the IDs.
    useTheme({
      operation: {
        cols: 1,
        hiddenSlots: ['security', 'parameters', 'responses', 'playground', 'code-samples'],
      },
    })
    openapiTheme.enhanceApp({ app })
  },
}
export default Theme
