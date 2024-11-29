{ lib
, stdenv
, fetchFromGitHub
, fetchYarnDeps
, yarnConfigHook
, yarnBuildHook
, yarnInstallHook
, nodejs
, electron
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "liascript-editor";
  version = "1.0.0";

  src = ../.;

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = ../yarn.lock;
    hash = lib.fakeHash;
  };

  nativeBuildInputs = [
    yarnConfigHook
    yarnBuildHook
    yarnInstallHook
    nodejs
    electron
  ];

  buildPhase = ''
    export HOME=$(mktemp -d)
    yarn build
  '';

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    
    # Copy built app
    cp -r dist $out/share/liascript-editor
    
    # Create wrapper script
    cat > $out/bin/liascript-editor <<EOF
    #!${stdenv.shell}
    exec ${electron}/bin/electron $out/share/liascript-editor
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

  meta = with lib; {
    description = "LiveEditor for LiaScript";
    homepage = "https://github.com/LiaScript/LiaScript-Editor";
    license = licenses.isc;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
})
