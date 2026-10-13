# Mr H mspaint addon viewer

A standalone Obsidian window with a **Settings → Viewer → Unload** button.
Addon controls appear when you install an addon. No built-in gameplay features.

## Launch

Run this in your Roblox executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/KoSmoXD/mspaintaddonsuser/main/viewer.lua"))()
```

Or download `viewer.lua` and execute it directly. Keep the launcher **outside**
`addonuser/addons`; that directory is for addons only.

## Add your addons

1. Start the viewer once. It creates `addonuser/addons` in your executor workspace.
2. Place an mspaint addon `.lua`, `.luau`, or `.txt` file directly in that folder.
3. Its controls appear automatically, normally within two seconds.

Editing a file reloads that addon. Removing it removes its UI. Unchanged files
are not repeatedly executed. Subfolders are not scanned. Press **Right Control**
to show/hide the window.

Use **Settings → Viewer → Unload** to stop scanning, clean up loaded addons, and
close the viewer. You can also unload from your executor:

```lua
getgenv().MrHAddonViewer:Unload()
```

Running the launcher again unloads the previous viewer first. Use this standalone
viewer instead of running the same addons in the official mspaint hub at the
same time, which would execute the addons twice.

## Compatibility

An addon must assign `mspaint.AddonInfo` first, with `Name`, `Title`, and `Game`.
`Description` is optional. The viewer provides:

- `mspaint.Groupbox`, created only when an addon accesses it.
- `mspaint.Library` and global `Library`, including `Window` for custom tabs.
- Addon-local `Options` and `Toggles`; UI control IDs are namespaced per file.
- `Library:OnUnload(callback)` and `Library:GiveSignal(connection)` cleanup.
- `mspaint.CurrentLanguage = "en"` and capability-presence checks through
  `mspaint.ExecutorSupport` (these are **not** a full UNC test).
- `Game = "*"`, numeric place/universe IDs, lists of filters, and DOORS aliases
  `doors/doors` and `doors/lobby`. Other string game aliases are skipped.
- Legacy toggle `Func` callbacks are translated to Obsidian `Callback`.

This is a compatibility host, **not the official mspaint runtime**. It does not
provide mspaint authentication, Discord account data, or private game modules.
Addons depending on those internals need changes. Normal Obsidian control
methods are forwarded; APIs that create additional windows are not supported.

Addons are executable scripts with the executor's capabilities, not sandboxed
previews. Only put trusted files in the folder. On reload/removal, an addon must
clean up its own spawned tasks, connections, world objects, and gameplay changes
using `Library:OnUnload`; the viewer cannot undo arbitrary script side effects.
Errors are reported in the developer console and in a visible Load error tab.
Wrong-game addons also explain why they were skipped. A failed addon is retried
when its file changes. Removing the file removes its error tab.

Mr H addon and Tplay addons require the full mspaint runtime; install those in
`mspaint/addons` and launch mspaint inside a DOORS run. This viewer does not
implement their required base features. Compatible addons can access the host
through `getgenv().mspaint` or nested `loadstring` URL loaders.

Requirements: executor filesystem functions (`listfiles`, `readfile`, `isfolder`,
`makefolder`), `loadstring`, `setfenv`, and HTTP access. Obsidian is fetched from
its upstream repository at launch and is not bundled here.

## Validation

Run the mock host tests with Lua 5.3+:

```sh
lua tests/viewer_spec.lua
```

These test loader behavior and API forwarding, not Roblox rendering or executor
compatibility. A live Roblox/executor test is still required.

References: [mspaint addon API](https://docs.mspaint.cc/addons/api),
[Obsidian](https://github.com/deividcomsono/Obsidian).
