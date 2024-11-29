{
  description = "Flake for LiaScript Editor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.callPackage ./pkgs/liascript-editor.nix { };

        devShell = pkgs.mkShell {
          buildInputs = with pkgs; [
            electron
            nodejs
            yarn
          ];
          
          shellHook = ''
            export ELECTRON_OVERRIDE_DIST_PATH=${pkgs.electron}/bin/electron
          '';
        };
      }
    );
}
