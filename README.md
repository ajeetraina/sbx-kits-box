# sbx-kits-box - Box Mount kit (private / local-only)

An [sbx](https://docs.docker.com/ai/sandboxes/) kit that brings Box's **Box Mount**
client into a sandbox: mount a Box folder into the sandbox and keep it in two-way
sync, with the Box access token injected by the sbx proxy (the real token never
enters the container).


## What's in here

```
sbx-kits-box/
├── spec.yaml                       # the kit (v2 mixin): Box network policy + token injection + agent instructions
├── Dockerfile                      # bakes box-mount into an image, arch-agnostic via TARGETARCH (too big for files/)
├── scripts/build-and-load.sh       # build a multi-arch image (both arches you staged) + load it into the sbx runtime
├── scripts/push-to-dockerhub.sh    # build + push a multi-arch image to a Docker Hub namespace you pass in (e.g. box)
├── box-mount/                       # (contents below are PRIVATE - git-ignored, obtain from Box)
│   ├── README.md                   # upstream Box Mount CLI docs (Box Confidential)
│   ├── linux/amd64/box-mount       # linux/amd64 binary  -> amd64 sandbox (Intel / Windows)
│   ├── linux/arm64/box-mount       # linux/arm64 binary  -> arm64 sandbox (Apple Silicon)
│   └── mac/box-mount               # darwin/arm64 binary -> HOST use only (not the sandbox)
└── README.md
```

> **The `box-mount/` binaries and docs are NOT in this repo.** They are Box
> private-preview artifacts and are **git-ignored**. Obtain them from Box and drop
> them into `box-mount/<arch>/` locally before building. This public repo ships
> only the kit scaffolding (spec, Dockerfile, scripts, docs).

The kit (`spec.yaml`) supplies only the **Box network allowlist**, **credential
injection**, the **`BOX_ACCESS_TOKEN` sentinel**, and the **agent instructions**. The
binary itself is delivered via a locally-built image (see below), because kit
`files/` are capped at a 4 MB injection message and the binary is ~34 MB.

> **v0.4.0 naming.** The current build ships as **`box-mount`**, and its `mount`
> command self-invokes a helper executable named `box-mount` on `PATH` (the sync
> engine). The Dockerfile installs the binary as **both** `box-mount` (required) and
> `agent-mount` (back-compat alias), so either command works inside the sandbox.

> **Private preview.** The `box-mount` binaries are Box private-preview artifacts and
> are **git-ignored** - not committed here. Obtain them from Box and stage them at
> `box-mount/linux/amd64/box-mount` and/or `box-mount/linux/arm64/box-mount` before
> building. Box ships both amd64 and arm64 Linux builds.

---

## Architecture (works for both amd64 and arm64)

A sandbox can only run an image that **matches the sbx runtime's architecture** — the
runtime does **not** emulate. This kit builds for **both** arches so the same tooling
works on Apple Silicon and Intel/amd64 alike:

| Your host / sbx runtime  | Binary you stage                | Status |
|--------------------------|---------------------------------|--------|
| `x86_64` (amd64)         | `box-mount/linux/amd64/box-mount` | ✅ works |
| `aarch64` (Apple Silicon)| `box-mount/linux/arm64/box-mount` | ✅ works |

`build-and-load.sh` builds **every arch you have staged** into one multi-arch image
via `docker buildx` (the `TARGETARCH`-aware Dockerfile bakes the right binary into
each). The loaded template — and the saved OCI tar — run on **both** arches, so you
can build once and reuse the artifact anywhere. Stage only your own arch and you get
a single-arch image for this host; that still works, it just won't run elsewhere.

Check a runtime's arch: `sbx exec <any-sandbox> -- uname -m`  (`x86_64` or `aarch64`).

---

## Quick start (local-only)

### 1. Obtain the Box binary and recreate the `box-mount/` structure

This public repo ships **scaffolding only** - the Box binaries are private-preview
artifacts and are **not** committed (they are git-ignored). A fresh clone therefore
has no `box-mount/` directory, and `build-and-load.sh` will fail with
`ERROR: no box-mount binary staged` until you stage at least your host's arch.

Get the build from Box (the `box-mount-0.4.0-linux-<arch>.tar.gz` archives), then
stage the binaries under the arch-keyed layout **from the repo root**. Stage **both**
to build a multi-arch image; stage just your own arch for a single-arch build:

```console
# arm64 (Apple Silicon)
mkdir -p box-mount/linux/arm64
tar xzf /path/to/box-mount-0.4.0-linux-aarch64.tar.gz -C box-mount/linux/arm64
chmod +x box-mount/linux/arm64/box-mount
file box-mount/linux/arm64/box-mount     # sanity: should say  ELF ... ARM aarch64

# amd64 (Intel / Windows)
mkdir -p box-mount/linux/amd64
tar xzf /path/to/box-mount-0.4.0-linux-x86_64.tar.gz -C box-mount/linux/amd64
chmod +x box-mount/linux/amd64/box-mount
file box-mount/linux/amd64/box-mount     # sanity: should say  ELF ... x86-64
```

Target layout (all paths are git-ignored, so nothing here gets committed):

```
box-mount/
├── linux/amd64/box-mount    # amd64 sbx runtime (Intel / Windows)
├── linux/arm64/box-mount    # arm64 sbx runtime (Apple Silicon)
└── mac/box-mount            # host-side use only (not the sandbox)
```

The arch directory names are the Docker `TARGETARCH` values (`amd64`, `arm64`), which
is how the Dockerfile picks the right binary per platform.

### 2. Build the image and load it into the sbx runtime

```console
./scripts/build-and-load.sh
```

This builds `sbx-box:local` (FROM the stock shell template, with `box-mount` baked in
under both `box-mount` and `agent-mount`) for **every arch you staged**, and loads the
multi-arch result into sbx's image store via `sbx template load`. Nothing is pushed.
Uses `docker buildx`; the script warns if your host's arch isn't among those staged.

> **Docker must be running** before this step. If the daemon is down the build
> fails silently, the image is never loaded, and `sbx run --template …` later fails
> with a **500 pull failed** (sbx falls back to pulling a local-only image). Confirm
> with `docker version` (Server section present) and `sbx template ls`.

#### (Optional) Publish the image to Docker Hub

To share the image instead of loading it only into your local sbx runtime, push a
**multi-arch** image to Docker Hub. Pass the namespace you own as the first
argument (e.g. `box`) — the script has no hard-coded default. It publishes to
`<namespace>/sbx-box`. One `docker buildx` build covers every staged arch (the
`TARGETARCH` Dockerfile bakes the right binary per platform) and pushes a single
`:v0.4.0` + `:latest` multi-arch manifest, so consumers pull the binary matching
their runtime automatically.

```console
export DOCKERHUB_USERNAME=<your-hub-user>
export DOCKERHUB_TOKEN=<your-docker-hub-access-token>   # a Hub access token, NOT your password
./scripts/push-to-dockerhub.sh box                     # -> box/sbx-box
```

Overrides: `NAMESPACE=box …` instead of the positional arg, `VERSION=v0.4.1 …` to
change the tag, `PLATFORMS=linux/arm64 …` for a single-arch push. If
`DOCKERHUB_TOKEN` is unset the script assumes an existing `docker login` session.
Requires `docker buildx` (it creates a `sbx-box-builder` builder if needed).

> ⚠️ **The `box-mount/` binaries are Box-confidential.** Only push to a Docker Hub
> repo you intend to be **private** (or one you are cleared to publish). A public
> image would expose the private binary.

### 3. Store your Box token (kept out of the container)

Developer-token / static-access-token mode (the documented "developer token via
environment variable, no config file" path). The token is stored as an sbx secret
and injected by the proxy as `Authorization: Bearer …` on Box API calls. Note this
mode does **not** auto-refresh - only true OAuth (which also needs `client_id` +
`client_secret` + `refresh_token`) does, and this kit injects only the access token:

```console
echo "<your-box-developer-or-oauth-access-token>" | sbx secret set box
sbx secret ls            # confirm a 'box' service secret exists
```

> A Box **developer token** (Developer Console → Configuration → *Generate
> Developer Token*) is the quickest way to test; it lasts ~60 min. When it
> expires, re-run the `sbx secret set box` line with a fresh token and **recreate
> the sandbox** (the proxy binds the secret at creation).

### 4. Run the sandbox with the template + this kit

```console
sbx run shell --template sbx-box:local --kit ./ .
```

### 5. Use Box Mount inside the sandbox

```console
box-mount --version
box-mount mount "/home/agent/workspace/box" "<box-folder-id>"   # folder id = number at the end of the box.com folder URL (root = 0)
box-mount status
box-mount unmount "/home/agent/workspace/box"
```

(`agent-mount` works too - it's an alias for the same binary.)

---

## Verify

```console
# binary present and runs (matches runtime arch)
sbx run shell --template sbx-box:local --kit ./ -- box-mount --version

# the env var holds the sentinel, NOT the real token (proxy swaps it on outbound)
sbx run shell --template sbx-box:local --kit ./ -- printenv BOX_ACCESS_TOKEN
# -> proxy-managed

# credential injection works: a Box API call from inside the sandbox returns 200
sbx run shell --template sbx-box:local --kit ./ -- \
  curl -s -o /dev/null -w '%{http_code}\n' https://api.box.com/2.0/users/me
# -> 200
```

Two-way sync smoke test, once mounted:

```console
# down-sync: the mount lists the Box folder's files
box-mount mount "/home/agent/workspace/box" "0" && ls /home/agent/workspace/box

# up-sync: a file created in the mount appears in Box within a few seconds
echo hi > /home/agent/workspace/box/e2e.txt        # then check box.com / the Box API
```

---

## Evaluating on Windows (amd64)

The `box-mount/linux/amd64/box-mount` binary is **linux/amd64**. On an amd64 sbx
runtime (a Windows machine - Docker Desktop's VM is `x86_64` on amd64 hardware, WSL 2
**or** Hyper-V backend) it execs fine. You don't need bash/WSL - the underlying steps
are three `docker`/`sbx` commands that run in native **PowerShell** (`--platform` sets
`TARGETARCH`, so the Dockerfile picks the amd64 binary automatically - no `BIN` arg):

```console
# from the repo root (PowerShell) - replaces build-and-load.sh, no bash needed
docker version                  # FIRST: confirm the Docker daemon is running (Server section present)
docker build --platform linux/amd64 -t sbx-box:local .
docker save sbx-box:local -o sbx-box.tar
sbx template load sbx-box.tar

sbx template ls                 # confirm sbx-box:local is now in sbx's store
# (if it's not listed, --template will try to PULL it and fail with a 500 - see Troubleshooting)

# Box token - interactive paste (avoids PowerShell pipe encoding mangling the token)
sbx secret set box
```

> Shortcut: you can also build the tar **on an Apple Silicon Mac**
> (`docker build --platform linux/amd64 …` then `docker save`) - the build only
> *copies* the binary, never execs it, so cross-building works. Copy `sbx-box.tar`
> to Windows and just run `sbx template load sbx-box.tar` there.

---

## Running in Docker Cloud (`sbx --cloud`)

With `sbx --cloud` the sandbox runs **server-side in Docker's cloud** (Linux microVMs),
not on your machine. This is the ideal setup when you develop on a Mac but want Box
Mount and the sandbox running in Linux in the cloud: your Mac only drives the CLI.
Docker Cloud runs **amd64**, and this kit builds an amd64 image from the same source as
your local arm64 build — so you develop on Apple Silicon and run amd64 in the cloud
without a separate cross-build.

Two differences from local runs: a custom template must be **uploaded to the cloud
registry first** (`--template` never auto-uploads, and it must be a **docker-save** tar,
not a buildx OCI tar), and — see the **Box token** note below — the kit's proxy-injected
`box` credential is **not yet accepted by the cloud secret store**, so the token is
passed as an env var into the cloud sandbox instead.

```console
# 0. Sign in (a Docker account with Cloud Sandboxes access)
sbx login

# 1. Build an amd64 image and export a DOCKER-SAVE tar. Docker Cloud runs amd64, and
#    `sbx template load --cloud` needs docker-save format (manifest.json) — a buildx
#    OCI tar (index.json) is rejected with "file manifest.json not found in tar".
docker build --platform linux/amd64 -t sbx-box:cloud .
docker save sbx-box:cloud -o /tmp/sbx-box.tar

# 2. Upload it as a cloud-managed template (~600 MB; takes a few minutes)
sbx template load /tmp/sbx-box.tar sbx-box --cloud --cpus 2 --memory-mib 4096

# 3. Run the sandbox in the cloud with this kit (amd64 Linux).
#    The cloud secret store rejects the kit's custom `box` service
#    (`sbx --cloud secret set box` -> unknown service "box"), so pass the token as an
#    env var. NOTE: unlike the local proxy path, the real token then lives INSIDE the
#    sandbox — use a short-lived developer token and delete the sandbox when done.
sbx --cloud run shell --template sbx-box --kit ./ -e BOX_ACCESS_TOKEN=<your-box-token>

# 5. Use Box Mount inside the cloud sandbox
sbx --cloud ls                                                    # find the sandbox name
sbx --cloud exec <sandbox> -- box-mount --version
sbx --cloud exec <sandbox> -- box-mount mount /home/agent/workspace/box <box-folder-id>
```

> ⚠️ **Confidential upload.** The tar carries the private `box-mount` binary. It goes
> to **your own** Docker Cloud account's template registry - treat it as private and
> don't share the template with accounts you aren't cleared for.

Notes:
- **Box token (cloud limitation).** The cloud secret store accepts only built-in
  services (`anthropic, aws, cursor, droid, github, google, groq, mistral, nebius,
  openai, xai`), so `sbx --cloud secret set box` fails with `unknown service "box"` —
  the kit's proxy-injected `box` credential works locally but isn't available in cloud
  yet. Workaround: pass the token with `-e BOX_ACCESS_TOKEN=<token>` at run time, which
  puts the real token **inside** the sandbox (no proxy indirection). Prefer a
  short-lived developer token and `sbx --cloud rm` the sandbox when finished.
- **Resources.** `--cpus` is one of 1/2/4/8/16 and `--memory-mib` is 512–32768 at a
  2:1 / 1:1 / 1:2 memory-to-CPU ratio; `--cpus 2 --memory-mib 4096` is a safe default.
  A cloud `run` without overrides defaults to 2 CPUs / 4 GiB (well above the 1 GiB a
  constrained local run can fall back to).
- **Tar format.** `sbx template load --cloud` parses **docker-save** archives
  (`manifest.json`). A buildx OCI export (`--output type=oci`, `index.json`) is
  rejected — use `docker build` + `docker save` as above. The amd64 template is
  single-platform, so no `--platform` flag is needed at run time.
- **Network egress.** The kit's Box allowlist (`spec.yaml`) travels with `--kit`. If a
  Box host is still blocked in the cloud, find it with `sbx --cloud policy log
  <sandbox>` and allow it (`--allow-network` at create time, or a policy allow).
- **Workspace.** Cloud sandboxes don't bind-mount your Mac's local folders like local
  mode does - Box Mount syncs Box content straight into the sandbox, so you usually
  don't need a local workspace there. To bring in a git repo add `--clone`; to copy
  files use `sbx cp`.
- **Lifecycle.** `--ttl 2h` sets a time-to-live, `sbx attach <sandbox>` reconnects, and
  `sbx move` shuttles a sandbox between local and cloud.

> The `--cloud` surface is evolving and some flags are experimental. If flags differ on
> your `sbx` version, check `sbx --cloud <verb> --help` and the official docs:
> https://docs.docker.com/ai/sandboxes/

---

## How auth works

`box-mount` sends `Authorization: Bearer proxy-managed` to Box; the sbx proxy
replaces the `proxy-managed` sentinel with the real token from `sbx secret set box`
on outbound requests to the allowlisted Box hosts. The real token is never present
in the container, and `BOX_ACCESS_TOKEN` only ever reads as `proxy-managed` inside
the sandbox.

`box-mount` consumes the `BOX_ACCESS_TOKEN` env var directly - the documented
"developer token via environment variable, no config file needed" path - so it runs
in static-access-token mode and sends *some* token, which the proxy overwrites on
the wire.

**Do not** run `box-mount config` inside the sandbox. (Note: a
`~/.box-mount/box-config.json` would **not** override the env token - per the
Box Mount docs, *environment variables take precedence over file values*, and the
proxy overwrites the header regardless.) The reason to avoid `config` is different:
it runs an interactive OAuth/JWT handshake and can write `client_id` /
`client_secret` / `refresh_token` or `auth_type=jwt`, flipping the client out of
the simple static-token mode the proxy relies on. You don't need it - the kit
already supplies the token via env.

Full JWT / service-account mode has **no token expiry** (the SDK mints short-lived
assertions), which is attractive for longer sessions - but it needs the keypair JSON
*inside the container*, the opposite of this proxy/secret model, so it's a separate
setup.

---

## Troubleshooting

- **`FileNotFoundError: [Errno 2] No such file or directory: 'box-mount'` on mount** -
  the v0.4.0 `mount` command self-invokes a `box-mount` executable on `PATH`. If the
  binary was installed only as `agent-mount`, this fails. The Dockerfile installs it
  as `box-mount` (and `agent-mount`); rebuild if you see this. *(Found during arm64
  end-to-end bring-up.)*

- **`Cannot determine minimum Box Mount version allowed, exiting` (HTTP 403 from
  `cdn07.boxcdn.net/AgentMount.json`)** - the sync engine's startup version check
  hit a host that wasn't allowlisted, and the proxy default-denied it (403). Fix:
  `*.boxcdn.net` is in `permissions.network.allow` in `spec.yaml`; if a new CDN host
  appears, widen it. Find blocked hosts with `sbx policy log <sandbox-name>`.

- **`500 ... pull failed for image 'sbx-box:local'`** - the template image
  isn't in sbx's store, so `--template` fell back to pulling it from a registry (it's
  local-only - there's nothing to pull). The build/save/load didn't complete, usually
  because **Docker wasn't running** during `docker build`. Confirm with `docker
  version`, rebuild, `sbx template load sbx-box.tar`, then verify with `sbx template ls`.

- **`ERROR: unknown flag: --template`** - the `sbx` on that machine is too old / a
  different build. Check `sbx version`; `sbx run --help` should list `-t, --template`.

- **`403 Blocked by network policy` on mount** - the host the SDK reached isn't in
  the allowlist. Find it and add it to `permissions.network.allow` in `spec.yaml`:
  ```console
  sbx policy log <sandbox-name>
  ```
  The starting allowlist is `api.box.com`, `upload.box.com`, `dl.boxcloud.com`,
  `*.boxcloud.com`, `*.services.box.net`, `*.boxcdn.net` (the `services.box.net`
  entry covers the events long-poll used for two-way sync; widen here if sync stalls).

- **`box-mount: not found` / exec format error** - architecture mismatch; see the
  Architecture section above. Confirm with `sbx exec <sandbox> -- uname -m`.

- **`failed to create sandbox: failed to run sandbox container`** - the loaded image
  has no variant for this host's arch (e.g. an arm64-only image on an amd64 host). The
  sbx runtime does **not** emulate. Confirm the mismatch:
  ```console
  uname -m                                                        # host arch, e.g. x86_64
  docker image inspect sbx-box:local --format '{{.Architecture}}' # image arch
  ```
  Fix: stage the host's arch and rebuild. `build-and-load.sh` builds a multi-arch
  image from every arch you staged, so staging **both** produces one image that runs
  on either host:
  ```console
  mkdir -p box-mount/linux/amd64
  # stage the amd64 box-mount at box-mount/linux/amd64/box-mount (obtain from Box)
  file box-mount/linux/amd64/box-mount       # sanity: should say  ELF ... x86-64
  ./scripts/build-and-load.sh                # builds every staged arch into one image
  sbx run shell --name box --template sbx-box:local --kit ./ .
  ```

- **`401 Unauthorized` from Box** - the token is invalid/expired. Developer tokens
  last ~60 min and cannot be refreshed under this kit (there's no refresh token, and
  a refresh POST carries client creds in the body, not the `Bearer` header the proxy
  injects). Fix: get a fresh token, `sbx secret set box`, and **recreate the
  sandbox** (the proxy binds the secret at creation time). To confirm whether it's
  the token vs. injection, test the token host-side:
  `curl -H "Authorization: Bearer <token>" https://api.box.com/2.0/users/me` - a 200
  means the token is good and the sandbox just needs recreating with the fresh secret.

- **`mount`/`status` work but file downloads 401** - Box download redirects often
  land on a `*.boxcloud.com` shard. It's network-allowed and covered by the
  `*.boxcloud.com` credential inject, but if you see a redirect host in `sbx policy
  log` that isn't getting a Bearer header, add it to the `credentials.inject` block.

- **Lost Box version history on save** - Box Mount doesn't support atomic-save
  (temp-file + rename); edit files in place inside the mount.

---

## Host-side binaries (not part of the sandbox)

The `box-mount/mac/box-mount` (darwin/arm64) and Windows builds run Box Mount
**on your host machine**, not inside the sandbox, and are **not** used by the kit.
Like the Linux binaries they are Box private-preview artifacts - obtain them from
Box; they are git-ignored, not shipped in this repo. Only a **Linux** binary
belongs inside an sbx sandbox.
