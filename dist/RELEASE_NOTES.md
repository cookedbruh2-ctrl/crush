# Crush v0.5.0 — Windows Installer

## Download

**Windows x64 setup (individual installer):**

- [`crush_0.5.0_x64-setup.exe`](./crush_0.5.0_x64-setup.exe)

SHA-256: `f17a241eacb662f6de320f4d2462f2440e239ebc621200f32cdb311a440ef90e`

## Installer details

- Native Windows PE (`x86_64`) GUI setup
- Installs to `%LocalAppData%\Crush` (no admin required)
- Start Menu + Desktop shortcuts
- Add/Remove Programs uninstall entry
- Registers `roblox://` and `roblox-player://` deep links
- Silent install: `crush_0.5.0_x64-setup.exe /S`
- Uninstall: `Uninstall Crush.exe --uninstall` or via Settings → Apps

## Build it yourself

```bash
# requires Zig on PATH
npm run build:installer
# or
bash scripts/build-windows-installer.sh
```

Source: `installer/main.zig`
