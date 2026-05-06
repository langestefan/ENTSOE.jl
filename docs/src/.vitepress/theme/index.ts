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
import { theme as openapiTheme, useOpenapi } from 'vitepress-openapi/client'
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
    // Single-column layout reads better on documentation sites; two-column
    // mode (the default) crams the playground next to the schema.
    useOpenapi({ spec, config: { operation: { cols: 1 } } })
    openapiTheme.enhanceApp({ app })
  },
}
export default Theme
