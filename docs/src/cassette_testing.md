# Recorded HTTP tests with BrokenRecord

This tutorial walks through writing a deterministic test for an endpoint
in `ENTSOE.jl` using
[BrokenRecord.jl](https://github.com/JuliaTesting/BrokenRecord.jl).

The package's test scaffold already includes `test/test-cassettes.jl`,
which configures BrokenRecord and creates `test/cassettes/`. This page
fills in the steps you take from there.

## Why cassettes

Tests that hit real HTTP services are slow and flaky — your CI fails
when the upstream is down, when rate limits kick in, or when the network
hiccups. BrokenRecord records the response of an HTTP call to disk on
the first run, then replays it from disk on every subsequent run. The
test becomes a pure function of the cassette file — fast, deterministic,
and offline.

The mode is decided purely by **whether the cassette file exists**:

| Cassette file | What `playback` does |
|---|---|
| Doesn't exist | Real HTTP call. Request and response are saved to the file. |
| Exists | Replays the recorded response. Verifies the request shape matches. |

To re-record, delete the cassette file and run the test again.

## 1. Install BrokenRecord

It's an opt-in dep — the test scaffold doesn't require it by default
because most users want to wire cassettes only for a few endpoints.

```julia-repl
pkg> activate test
(test) pkg> add BrokenRecord@0.1
```

## 2. Construct a `Client` and an API set

The generated low-level API ships in `src/api/`. Each tag becomes a
struct (`PetApi`, `StoreApi`, …) that takes an
`OpenAPI.Clients.Client` — accessible as `client.inner` on the
hand-written wrapper:

```julia
using ENTSOE

client  = Client("https://api.example.com"; auth = NoAuth())
pet_api = PetApi(client.inner)
```

That's the only generated-vs-hand-written boundary you have to know
about; everything else stays on `Client`.

## 3. Write the first cassette test

In `test/test-cassettes.jl`, replace the commented example block with
real `@testset`s. Each test wraps its endpoint call in
`BrokenRecord.playback`:

```julia
@testset "GET /pet/{petId} — id 1" begin
    pet, _http = BrokenRecord.playback("get_pet_1.yml") do
        get_pet_by_id(pet_api, 1)
    end
    @test pet isa Pet
    @test pet.id == 1
end
```

Two things to know:

- Generated operation names are **snake_case**: spec `getPetById` →
  `get_pet_by_id`, `findPetsByStatus` → `find_pets_by_status`.
- Each operation returns `(parsed_result, http_response)`. Almost
  always you destructure the response and ignore the second value:
  `pet, _ = get_pet_by_id(pet_api, 1)`.

## 4. Record the cassette

The first run is the only one that needs network access:

```bash
julia --project=. -e 'using Pkg; Pkg.test()'
```

You should see `test/cassettes/get_pet_1.yml` appear (default extension
is `.yml`; pass `extension="bson"` to `BrokenRecord.configure!` if you
want compact binary). Open the file — it's the recorded HTTP exchange
with the headers listed in `ignore_headers` already redacted.

Commit the cassette:

```bash
git add test/cassettes/get_pet_1.yml
git commit -m "test: cassette for GET /pet/{petId}"
```

## 5. Replay everywhere else

From now on every `Pkg.test()` replays from disk. CI doesn't need the
upstream API to be reachable, doesn't need credentials, and runs in
milliseconds:

```bash
JULIA_NO_NETWORK=1 julia --project=. -e 'using Pkg; Pkg.test()'   # still passes
```

## 6. Tests with auth

Cassettes redact credential-bearing headers via the `ignore_headers`
option already configured in `test-cassettes.jl`
(`Authorization`, `X-API-Key`, `Cookie`, `Set-Cookie`,
`Proxy-Authorization`). Token query params (`api_key`, `token`,
`access_token`) are scrubbed via `ignore_query`. So tests like the
following are safe to commit:

```julia
@testset "POST /pet" begin
    authed     = Client("https://api.example.com"; auth = BearerToken("secret"))
    authed_pet = PetApi(authed.inner)

    new_pet = Pet(; name = "doggie", photoUrls = ["https://example.com/dog.jpg"])
    saved, _ = BrokenRecord.playback("add_pet.yml") do
        add_pet(authed_pet, new_pet)
    end
    @test saved.name == "doggie"
end
```

The `"secret"` token is in the request *while recording*, but the
recorded cassette only contains `Authorization: [redacted]`.

If your API uses a non-standard auth header or a token in the query
string, extend the redaction list in `test-cassettes.jl`:

```julia
BrokenRecord.configure!(;
    path = _CASSETTES_DIR,
    ignore_headers = [..., "X-Custom-Auth"],
    ignore_query   = [..., "session_id"],
)
```

## 7. Re-recording

When the upstream API changes shape — new fields, removed fields,
schema bump — your replay tests will fail because the recorded
response no longer matches what the parser expects.

To re-record one cassette:

```bash
rm test/cassettes/get_pet_1.yml
julia --project=. -e 'using Pkg; Pkg.test()'   # records, then replays
git diff test/cassettes/get_pet_1.yml          # review the change
git add test/cassettes/get_pet_1.yml
```

To re-record everything (after a major upstream version bump):

```bash
rm -rf test/cassettes/
mkdir   test/cassettes/
julia --project=. -e 'using Pkg; Pkg.test()'
```

## Patterns that pay off

- **One cassette per endpoint, not per assertion.** Many `@test`s can
  live inside a single `playback` block. That keeps cassette count
  manageable and makes the recorded interaction easier to review.
- **Use minimal request bodies.** A short request makes a short cassette,
  which makes the eventual diff comprehensible.
- **Don't record `429`s.** Rate-limit handling belongs in mocked tests
  (`test-mocking.jl`) where you control the response with `Mocking.jl`.
  Reserve cassettes for the happy path and one or two semantic 4xx
  responses (404, 400) you actually want to assert against.
- **Inspect the YAML before committing.** Confirm the redaction did its
  job — search for any leftover token, header value, or query param.

## End-to-end worked example

The transcript below is the actual output from running this tutorial
against the **Petstore v2 demo** (the reference scaffold shipped by
[OpenAPITemplate.jl](https://github.com/langestefan/OpenAPITemplate.jl)).
It exercises four endpoints — `/store/inventory`, `/pet/findByStatus`,
`/store/order`, and `/pet` — and demonstrates the three-mode cycle
(record → replay → re-record). Use it as a sanity check that your own
setup matches.

### 1. Install BrokenRecord

```text
$ julia --project=test -e 'using Pkg; Pkg.add(name="BrokenRecord", version="0.1")'
   Installed BrokenRecord ─ v0.1.10
  [bdd55f5b] + BrokenRecord v0.1.10
```

### 4. First run — records 4 cassettes

```text
$ ls test/cassettes/      # before
(empty)
$ julia --project=. -e 'using Pkg; Pkg.test()'
Test Summary:       | Pass  Total  Time
Cassettes           |   10     10  13.4s
     Testing PetstoreV2 tests passed
$ ls test/cassettes/      # after
add_pet.yml  find_pets_available.yml  place_order.yml  store_inventory.yml
```

### 5. Replay run — fully offline

```text
$ JULIA_NO_NETWORK=1 julia --project=. -e 'using Pkg; Pkg.test()'
Test Summary:       | Pass  Total  Time
Cassettes           |   10     10  14.3s
     Testing PetstoreV2 tests passed
```

### 6. Verify auth redaction

```text
$ grep 'special-key' test/cassettes/add_pet.yml
(no match — secret was stripped)

$ grep -E '^      - (api_key|Authorization|X-API-Key)' test/cassettes/add_pet.yml
(no credential headers in the cassette at all)
```

### 7. Re-record one cassette

```text
$ md5sum test/cassettes/store_inventory.yml
49660c906e888c670f936b47ae59737d  store_inventory.yml

$ rm test/cassettes/store_inventory.yml
$ julia --project=. -e 'using Pkg; Pkg.test()'
Cassettes           |   10     10  19.2s
     Testing PetstoreV2 tests passed

$ md5sum test/cassettes/store_inventory.yml
a7d8260bdd15e0e78cf6d449d2e6e62d  store_inventory.yml      # ← refreshed
```

All three runs (record / replay / re-record) exit 0 with `10/10` passing
assertions.
