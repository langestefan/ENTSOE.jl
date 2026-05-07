exclude = [
  # Documenter cross-refs / Pkg cite refs are not URLs.
  "@ref",
  "@cite",
  # Skip un-tagged release URLs while versions are still in flux.
  "^https://github.com/.*/releases/tag/v.*$",
  # Placeholder DOI — replace with the real one once registered.
  "^https://doi.org/FIXME$",
  "zenodo.org/badge/DOI/FIXME$",
]

# Generated artefacts and pinned spec mirrors.
exclude_path = [
  "docs/build",
  "src/api",
  "spec",
]
