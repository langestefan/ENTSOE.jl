[default.extend-words]
# Domain-specific tokens that the heuristics flag as misspellings. Add
# more as new false positives surface. Two-letter ISO / EIC fragments
# like "BA" (Bosnia & Herzegovina), "BE", "FI" etc. show up inside
# 16-character EIC strings such as "10YBA-JPCC-----D".
BA = "BA"
ELES = "ELES"     # Slovenian TSO acronym, embedded in their EIC code
YSE = "YSE"       # appears inside Swedish EIC "10YSE-1--------K"

[files]
# `src/api/` is openapi-generator output. Treating it as authoritative
# means false positives there don't block CI; the regen workflow
# refreshes it from spec changes upstream.
extend-exclude = [
  "src/api/**",
  "spec/openapi.json",
  "spec/openapi.yaml",
  "spec/*.postman_collection.json",   # upstream-vendor dump, not our prose
  "test/cassettes/**",                 # recorded XML responses (random hex IDs)
  "test/cassettes_smoke/**",
  "docs/src/public/**",                # vendored copies of the spec for the docs browser
  "docs/src/assets/*.json",            # data fixtures embedded in tutorials
  "Manifest.toml",
  "docs/build/**",
  "docs/Manifest.toml",
]

[type.ipynb]
# Avoid false positives in the base64 image blobs inside notebooks.
extend-glob = ["*.ipynb"]
check-file = false
