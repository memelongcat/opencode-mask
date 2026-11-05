# shell configuration with dev tools for Nix users

{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    gnumake
    # pre-commit
    # shellcheck
  ];
}
