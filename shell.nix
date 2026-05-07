{ pkgs ? import <nixpkgs> {} }:

let
  dynamicLinker = pkgs.stdenv.cc.bintools.dynamicLinker;
  runtimeLibs = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc
    pkgs.zlib
    pkgs.openssl
    pkgs.xz
    pkgs.sqlite
    pkgs.curl
  ];
in
pkgs.mkShell {
  name = "claude-fixed";

  buildInputs = with pkgs; [
    bash
    coreutils
    curl
    wget
    jq
    gnugrep
    gnused
    findutils
    patchelf
    file
    glibc
    zlib
    openssl
    xz
    sqlite
  ];

  shellHook = ''
    export CLAUDE_INSTALL_SCRIPT_URL="https://claude.ai/install.sh"
    export CLAUDE_NIXOS_LINKER="${dynamicLinker}"
    export CLAUDE_NIXOS_RPATH="${runtimeLibs}"
    export PATH="$HOME/.local/bin:$PATH"

    patch_binary() {
      local bin="$1"
      local real_bin

      real_bin="$(readlink -f "$bin" 2>/dev/null || printf '%s\n' "$bin")"

      if [ ! -f "$real_bin" ]; then
        echo "Binary not found: $bin" >&2
        return 1
      fi

      if ! file "$real_bin" | grep -q 'ELF'; then
        echo "Skipping non-ELF file: $bin"
        return 0
      fi

      chmod +w "$real_bin" 2>/dev/null || true
      patchelf --set-interpreter "$CLAUDE_NIXOS_LINKER" "$real_bin"
      patchelf --set-rpath "$CLAUDE_NIXOS_RPATH" "$real_bin"
      echo "Patched $real_bin"
    }

    fix_installed_claude() {
      local candidates=(
        "$HOME/.local/bin/claude"
        "$HOME/.claude/local/claude"
      )
      local candidate

      for candidate in "''${candidates[@]}"; do
        if [ -f "$candidate" ]; then
          patch_binary "$candidate"
        fi
      done

      if [ -d "$HOME/.claude/local" ]; then
        while IFS= read -r -d ''' file_path; do
          patch_binary "$file_path"
        done < <(find "$HOME/.claude/local" -type f -perm -0100 -print0 2>/dev/null)
      fi

      if [ -d "$HOME/.local/share/claude/versions" ]; then
        while IFS= read -r -d ''' file_path; do
          patch_binary "$file_path"
        done < <(find "$HOME/.local/share/claude/versions" -maxdepth 1 -type f -print0 2>/dev/null)
      fi
    }

    install_claude_fixed() {
      local target="$1"
      local tmpdir install_script patched_script

      if [[ -n "$target" ]] && [[ ! "$target" =~ ^(stable|latest|[0-9]+\.[0-9]+\.[0-9]+(-[^[:space:]]+)?)$ ]]; then
        echo "Usage: install_claude_fixed [stable|latest|VERSION]" >&2
        return 1
      fi

      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' RETURN

      install_script="$tmpdir/install.sh"
      patched_script="$tmpdir/install-patched.sh"

      curl -fsSL "$CLAUDE_INSTALL_SCRIPT_URL" -o "$install_script"

      sed \
        -e '/chmod +x "\$binary_path"/a\
if [ "$os" = "linux" ]; then\
    patchelf --set-interpreter "$CLAUDE_NIXOS_LINKER" --set-rpath "$CLAUDE_NIXOS_RPATH" "$binary_path"\
fi\
' \
        "$install_script" > "$patched_script"

      chmod +x "$patched_script"
      bash "$patched_script" ''${target:+"$target"}
      fix_installed_claude
    }

    update_claude_fixed() {
      install_claude_fixed latest
    }

    echo ""
    echo "Claude Code NixOS shell"
    echo "Linker: $CLAUDE_NIXOS_LINKER"
    echo ""
    echo "Commands:"
    echo "  install_claude_fixed [stable|latest|VERSION]"
    echo "  update_claude_fixed"
    echo "  fix_installed_claude"
    echo ""
  '';
}
