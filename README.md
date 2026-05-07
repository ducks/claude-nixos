# claude-nixos

A `shell.nix` that makes Claude Code's official installer work on NixOS.

The official installer (`curl -fsSL claude.ai/install.sh | bash`) drops a
prebuilt Linux binary into `~/.local/bin/claude`. NixOS doesn't follow the
[Filesystem Hierarchy Standard](https://nixos.wiki/wiki/Packaging/Binaries)
so the binary's hardcoded dynamic linker path (`/lib64/ld-linux-x86-64.so.2`)
doesn't exist, and the binary refuses to run with some variant of:

```
Could not start dynamically linked executable
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box.
```

This repo provides a `nix-shell` environment that runs the official installer
and patches the binary on the way in using `patchelf`, so the installed
`claude` works the same as on any FHS distro.

## Usage

```bash
git clone https://github.com/ducks/claude-nixos
cd claude-nixos
nix-shell
```

Three functions become available in the shell:

| Command                          | What it does                                     |
|----------------------------------|--------------------------------------------------|
| `install_claude_fixed`           | Install latest, patched on the way in            |
| `install_claude_fixed 0.5.2`     | Install a specific version                       |
| `install_claude_fixed stable`    | Install the latest stable channel build          |
| `fix_installed_claude`           | Patch an existing install in `~/.local/...`      |
| `update_claude_fixed`            | Update to a newer version, patching as it goes   |

After `install_claude_fixed`, `claude --version` should work from any shell.

## How it works

The shell exports a `patch_binary` helper that takes a path to an ELF binary
and rewrites two things via `patchelf`:

- The interpreter path (`--set-interpreter`) is set to NixOS's actual
  dynamic linker, taken from `pkgs.stdenv.cc.bintools.dynamicLinker`.
- The rpath (`--set-rpath`) is set to a colon-joined list of `/nix/store`
  paths for the libraries Claude Code links against: glibc, libstdc++,
  zlib, openssl, xz, sqlite, curl.

For new installs, the shell downloads the official installer, uses `sed`
to inject `patchelf` calls right after the line that copies the binary
into place, then runs the modified script. This keeps the install path
identical to the upstream flow with one extra step inlined - so when
Anthropic ships a new installer, this keeps working as long as the basic
`cp ... claude ... $INSTALL_DIR` shape stays.

For existing installs, `fix_installed_claude` walks the standard locations
(`~/.local/bin`, `~/.claude/local`, `~/.local/share/claude/versions`) and
patches every executable ELF file it finds.

## Caveats

- Pinned to the libraries Claude Code currently needs. If a future release
  links against something new (a different TLS stack, a different
  compression library), you'll get a runtime error and need to add it to
  the `runtimeLibs` list in `shell.nix`.
- The `sed` injection is brittle by design: if the upstream installer
  restructures the copy step, you'll get a clean parse error instead of
  silently failing later.
- This doesn't affect anything system-wide. No `configuration.nix` change,
  no rebuild. Just a `nix-shell` that knows how to install Claude Code.

## Related

- [NixOS Wiki: Packaging/Binaries](https://nixos.wiki/wiki/Packaging/Binaries)
- [nix-ld](https://github.com/nix-community/nix-ld) - a system-wide alternative
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) - the tool this is for
