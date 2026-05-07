# https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md
default: true
# Long lines are common in tutorial prose; rely on the editor / prose
# linter for line-length, not markdownlint.
MD013: false
# Allow inline HTML — Documenter / Vitepress markdown often uses it.
MD033: false
# First line in file doesn't have to be a top-level heading; landing
# pages and license files start with frontmatter or boilerplate.
MD041: false
# Tutorial / API-reference pages often reuse small section headers
# ("Example", "Returns") inside different parents; that's fine in our
# context and would be noise to alias each one.
MD024:
  siblings_only: true
# Compact-style markdown tables (`|---|---|`) are valid GFM and our
# convention; don't force the padded variant.
MD060: false
