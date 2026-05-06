# lockedin-browser-cursor-version

This repository contains a small **Objective‑C injectable library** that turns the LockDown Browser **tab strip / inactive tab fill** (the ChromiumTabs `247/255` calibrated white) into **hot pink** (`#FF69B4`), plus a script that copies an existing LockDown Browser `.app`, embeds the library, sets a **labeled** bundle name, and **re-signs** the bundle ad hoc so it can run locally.

## Legal / academic integrity

LockDown Browser is proprietary software owned by Respondus. You must comply with its license, your institution’s policies, and applicable law. This tooling is provided for **local customization on copies you are allowed to modify**; redistribution of Respondus binaries may be restricted.

## Build the labeled app

1. Place a LockDown Browser `.app` on disk (or a folder whose layout is `Contents/MacOS/...`).
2. Run:

```bash
cd lockedin-browser-cursor-version
chmod +x scripts/package_hot_pink_app.sh
scripts/package_hot_pink_app.sh "/path/to/LockDown Browser.app"
```

If this repo sits next to a `Contents` folder (typical when opened as an app bundle in Cursor), you can omit the path:

```bash
scripts/package_hot_pink_app.sh
```

Output: `dist/LockedIn-Browser-Cursor-HotPink.app` with display name **LockedIn Browser · Hot Pink** and version **2.1.5-cursor-hotpink**.

The script adds `DYLD_INSERT_LIBRARIES` via `LSEnvironment` and applies the `com.apple.security.cs.disable-library-validation` entitlement so the hook library can load under a re-signed bundle.

The hook is built as a **universal** dylib (`x86_64` + `arm64`) because LockDown Browser’s main executable is **x86_64** (Rosetta on Apple Silicon); an **arm64-only** inject library makes dyld exit with *incompatible architecture*.

Helpers (GPU, Renderer, …) inherit `DYLD_INSERT_LIBRARIES`; `@executable_path` is relative to **each** helper. The packager therefore copies `libLockedInPinkTabs.dylib` into **every** nested `Contents/Frameworks/*.app` as well as the main app.

LockDown Browser also runs a **bundle seal check** (`SecStaticCodeCheckValidity` / `SecCodeCheckValidity`). After re-signing, that check would otherwise show *corrupt application bundle*. The inject library uses `DYLD_INTERPOSE` so those calls succeed during startup. This is inherently a **trust / integrity bypass** for that check only in processes that load the library—use accordingly.

## Repository

Tooling lives at [github.com/ReidT205/lockedin-browser-cursor-version](https://github.com/ReidT205/lockedin-browser-cursor-version). Optional: attach a zipped `dist/*.app` as a **Release** asset instead of committing Respondus binaries to git.
