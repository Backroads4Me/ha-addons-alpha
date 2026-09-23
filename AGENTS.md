Workspace rules: `../../AGENTS.md`

# ha-addons-alpha — Agent Guide

## This repo is DOWNSTREAM of beta and never reaches production

`ha-addons-alpha` carries short-lived test tooling, such as the Hughes protocol
probe, for a few hand-picked testers. It is a copy of `ha-addons-beta` plus that
tooling:

- **Source of truth for the add-on:** `../ha-addons-beta`. Author add-on changes
  there, not here.
- **Alpha-only work:** lives only here, in its own files wherever possible.
  Never copy it into beta or prod.
- **Never mirror alpha anywhere.** Nothing flows alpha → beta or alpha → prod,
  and this repo deliberately has no `mirror.sh`.

## Refreshing alpha from beta

```bash
alpha-notes/sync-from-beta.sh    # copies beta's librecoach/ over alpha's, keeping alpha-only files
```

The script keeps `librecoach/config.yaml` and the files listed in its
`ALPHA_ONLY` array, re-applies the probe registration in
`librecoach_ble/devices/__init__.py`, and flags `config.yaml` drift. Afterwards:

1. Port any flagged `options:`/`schema:` changes into alpha's `config.yaml` by
   hand, keeping alpha's `version:` and `image:` lines.
2. Set `version:` to `<newest CHANGELOG version>-alpha.<n>`, raising `<n>` for
   each build. The builder publishes only versions that GHCR does not have yet,
   and requires the base version to match the newest changelog entry.
3. Run the tests, review, commit and push `main`. Pushing `main` builds the
   `-alpha` images that alpha testers receive.

## Gotchas

- **Node-RED is an upstream build dependency.** The `Dockerfile` fetches the
  `librecoach-node-red` commit in `librecoach/node-red.ref` with the
  `NODE_RED_TOKEN` repository secret, a GitHub token with read access to that
  private repo. A sync from beta brings beta's pointer with it.
- Images use the `-alpha` suffix (`IMAGE_SUFFIX` in the builder), so they never
  replace beta or stable images.

## Alpha-only tooling

- Hughes Gen2 protocol probe: `alpha-notes/hughes-probe.md`

## Tests

BLE bridge tests run without Home Assistant installed (fakes live in `conftest.py`):

```bash
cd librecoach/librecoach_ble/tests && python3 -m pytest -q
```
