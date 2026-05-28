{
  description = "rules_tectonic: Bazel rules for compiling LaTeX to PDF with tectonic";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bazelisk
            tectonic
            git
            gh
            jq
            buildifier
          ];
          shellHook = ''
            echo "rules_tectonic dev shell"
            echo "  bazelisk $(bazelisk version 2>/dev/null | head -1)"
            echo "  tectonic $(tectonic --version 2>/dev/null | head -1)"
          '';
        };
      }
    );
}
