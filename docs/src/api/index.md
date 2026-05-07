# REST API Reference

This section is the interactive browser for the OpenAPI spec bundled with
[`EntsoE.jl`](../index.md). The spec is committed at
[`spec/openapi.json`](https://github.com/langestefan/EntsoE.jl/blob/main/spec/openapi.json)
and rendered with
[`vitepress-openapi`](https://github.com/enzonotario/vitepress-openapi).

```@raw html
<div class="custom-block warning">
  <p class="custom-block-title">Try-it-out and CORS</p>
  <p>Most public APIs do not enable CORS for arbitrary origins, so the
  in-browser <em>send request</em> button often fails with a CORS error
  against production hosts. The endpoint pages are still useful for
  browsing parameter shapes, response schemas, and copying generated
  request snippets.</p>
</div>
```

Endpoints are grouped by spec tag — pick one from the sidebar. Each tag's
page lists every operation as a top-level (`##`) heading so the right-hand
"On this page" outline can be used to jump between endpoints.
