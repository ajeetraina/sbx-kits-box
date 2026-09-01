# sbx-kits-box — Box AgentMount kit (private / local-only)

An [sbx](https://docs.docker.com/ai/sandboxes/) kit that brings Box's **AgentMount**
client into a sandbox: mount a Box folder into the sandbox and keep it in two-way
sync, with the Box access token injected by the sbx proxy (the real token never
enters the container).


---

## What's in here

```
sbx-kits-box/
├── spec.yaml                       # the kit (v2 mixin): Box network policy + token injection + agentContext
├── Dockerfile                      # bakes the agent-mount binary into a local image (binary is too big for files/)
├── scripts/build-and-load.sh       # build that image + load it into the sbx runtime
├── agentmount/
│   ├── README.md                   # upstream AgentMount CLI docs (Box)
│   ├── linux/agent-mount           # linux/amd64 binary  -> used inside the sandbox
│   └── mac/agent-mount             # darwin/arm64 binary  -> HOST use only (not the sandbox)
└── README.md
```

The kit (`spec.yaml`) supplies only the **Box network allowlist**, **credential
injection**, the **`BOX_ACCESS_TOKEN` sentinel**, and the **agent context**. The
binary itself is delivered via a locally-built image (see below), because kit
`files/` are capped at a 4 MB injection message and the binary is ~34 MB.

---

## ⚠️ Architecture requirement (read first)

A sandbox can only run a binary that **matches the sbx runtime's architecture**,
and the sbx runtime does **not** emulate other architectures.

| Your host / sbx runtime | Binary you need                  | Status here |
|-------------------------|----------------------------------|-------------|
| `x86_64` (amd64)        | `agentmount/linux/agent-mount` ✅ | works       |
| `aarch64` (Apple Silicon)| a **linux/arm64** `agent-mount`  | **not yet provided** |

Check your runtime arch:

```console
sbx run shell -- uname -m        # x86_64  or  aarch64
```

The bundled Linux binary is **linux/amd64 only**. On an Apple Silicon Mac the sbx
runtime is `aarch64`, so this binary will **not exec inside the sandbox** (plain
`docker run --platform linux/amd64` emulates it, but the sbx runtime does not). To
run locally on Apple Silicon you need a **linux/arm64** build of `agent-mount`;
drop it in and point the build at it:

```console
BIN=agentmount/linux-arm64/agent-mount ./scripts/build-and-load.sh
```

---

## Quick start (local-only)

### 1. Build the image and load it into the sbx runtime

```console
./scripts/build-and-load.sh
```

This builds `sbx-box-agentmount:local` (FROM the stock shell template, with
`agent-mount` baked in) and loads it into sbx's image store via `sbx template
load`. Nothing is pushed. The script warns if the binary arch won't match your
runtime.

### 2. Store your Box token (kept out of the container)

OAuth / developer-token mode. The token is stored as an sbx secret and injected
by the proxy as `Authorization: Bearer …` on Box API calls:

```console
echo "<your-box-developer-or-oauth-access-token>" | sbx secret set -g box
sbx secret ls            # confirm a 'box' service secret exists
```

> A Box **developer token** (Developer Console → Configuration → *Generate
> Developer Token*) is the quickest way to test; it lasts ~60 min. When it
> expires, re-run the `sbx secret set -g box` line with a fresh token.

### 3. Run the sandbox with the template + this kit

```console
sbx run shell --template sbx-box-agentmount:local --kit ./ .
```

### 4. Use AgentMount inside the sandbox

```console
agent-mount --version
agent-mount mount "/home/agent/workspace/box" "<box-folder-id>"   # folder id = number at the end of the box.com folder URL
agent-mount status
agent-mount unmount "/home/agent/workspace/box"
```

---

## Verify

```console
# binary present and runs (matches runtime arch)
sbx run shell --template sbx-box-agentmount:local --kit ./ -- agent-mount --version

# the env var holds the sentinel, NOT the real token (proxy swaps it on outbound)
sbx run shell --template sbx-box-agentmount:local --kit ./ -- printenv BOX_ACCESS_TOKEN
# -> proxy-managed
```

---

## Evaluating on Windows (amd64)

The bundled Linux binary is **linux/amd64 only**, so on an Apple Silicon Mac the
`aarch64` sbx runtime can't exec it (see the Architecture section). To evaluate the
kit end-to-end you need an **amd64** runtime — a Windows machine works, because
Docker Desktop's VM (WSL 2 **or** Hyper-V backend) is `x86_64` on amd64 hardware.
The Hyper-V vs WSL 2 choice does **not** change the architecture; both run the
amd64 binary fine.

You also don't need bash/WSL for this. `scripts/build-and-load.sh` is just a
convenience wrapper — the underlying steps are three `docker`/`sbx` commands that
run in native **PowerShell**:

```console
# from the repo root (PowerShell) — replaces build-and-load.sh, no bash needed
docker build --platform linux/amd64 -t sbx-box-agentmount:local .
docker save sbx-box-agentmount:local -o sbx-box.tar
sbx template load sbx-box.tar

# Box token — interactive paste (avoids PowerShell pipe encoding mangling the token)
sbx secret set -g box
```

> Shortcut: you can also build the tar **on an Apple Silicon Mac**
> (`docker build --platform linux/amd64 …` then `docker save`) — the build only
> *copies* the binary, never execs it, so cross-building works. Copy `sbx-box.tar`
> to Windows and just run `sbx template load sbx-box.tar` there.

Confirm it works:

```console
sbx run shell -- uname -m
# -> x86_64   (the reason you're on Windows)

sbx run shell --template sbx-box-agentmount:local --kit ./ -- agent-mount --version
# -> a version, NOT "exec format error"

sbx run shell --template sbx-box-agentmount:local --kit ./ -- printenv BOX_ACCESS_TOKEN
# -> proxy-managed   (sentinel, not the real token)
```

Then the functional check — mount a Box folder and confirm two-way sync:

```console
sbx run shell --template sbx-box-agentmount:local --kit ./ .
#   agent-mount mount "/home/agent/workspace/box" "<box-folder-id>"
#   agent-mount status
```

---

## How auth works

`agent-mount` sends `Authorization: Bearer proxy-managed` to Box; the sbx proxy
replaces the `proxy-managed` sentinel with the real token from `sbx secret set -g
box` on outbound requests to the allowlisted Box hosts. The real token is never
present in the container, and `BOX_ACCESS_TOKEN` only ever reads as `proxy-managed`
inside the sandbox.

Because of this, **do not** run `agent-mount config` or write
`~/.agent-mount/box-config.json` inside the sandbox — that would shadow the
proxy-injected token. (Full JWT / service-account mode, which needs the keypair
JSON inside the container, is a separate setup; this kit is wired for the OAuth /
developer-token path you selected.)

---

## Troubleshooting

- **A Box request is blocked** — find the missing host and add it to
  `caps.network.allow` in `spec.yaml`:
  ```console
  sbx policy log <sandbox-name>
  ```
  The starting allowlist is `api.box.com`, `upload.box.com`, `dl.boxcloud.com`,
  `*.boxcloud.com`, `*.services.box.net` (the last covers the events long-poll used
  for two-way sync; Box's realtime host names vary, so widen here if sync stalls).

- **`agent-mount: not found` / exec format error** — architecture mismatch; see the
  Architecture section above. Confirm with `sbx run shell -- uname -m`.

- **401 / auth errors after a while** — the OAuth/developer token expired. Refresh:
  `echo "<new-token>" | sbx secret set -g box`, then restart the sandbox.

- **Lost Box version history on save** — AgentMount doesn't support atomic-save
  (temp-file + rename); edit files in place inside the mount.

---

## Host-side binaries (not part of the sandbox)

`agentmount/mac/agent-mount` (darwin/arm64) and the Windows build are for running
AgentMount **on your host machine**, not inside the sandbox. They are kept here for
convenience and are **not** used by the kit. For host use, follow
[`agentmount/README.md`](agentmount/README.md) (run `agent-mount config`, etc.).
Only the **Linux** binary belongs inside an sbx sandbox.
