{
  description = "Flake for LiaScript Editor";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let 
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.mkYarnPackage {
          name = "liascript-editor";
          src = ./.;
          packageJSON = ./package.json;
          yarnLock = ./yarn.lock;

          buildInputs = with pkgs; [ 
            electron
            nodejs
            yarn
          ];

          buildPhase = ''
            export HOME=$(mktemp -d)
            yarn install --offline
            yarn build
          '';

          installPhase = ''
            mkdir -p $out/bin
            mkdir -p $out/share/applications
            
            # Copy built app
            cp -r dist $out/share/liascript-editor
            
            # Create wrapper script
            cat > $out/bin/liascript-editor <<EOF
            #!${pkgs.bash}/bin/bash
            exec ${pkgs.electron}/bin/electron $out/share/liascript-editor
            EOF
            chmod +x $out/bin/liascript-editor
            
            # Create desktop entry
            cat > $out/share/applications/liascript-editor.desktop <<EOF
            [Desktop Entry]
            Name=LiaScript Editor
            Exec=$out/bin/liascript-editor
            Icon=$out/share/liascript-editor/assets/logo.png
            Type=Application
            Categories=Development;Education;
            EOF
          '';
        };

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
