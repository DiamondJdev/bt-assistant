{
  description = "BT — voice-native assistant, dev environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            python311
            uv
            ffmpeg
            portaudio
            sqlite
            piper-tts
          ];

          shellHook = ''
            unset PYTHONPATH
            # numpy, onnxruntime and friends ship prebuilt wheels linked against the
            # system C++/zlib/audio libs, which a nix shell does not expose by default.
            export LD_LIBRARY_PATH="${
              pkgs.lib.makeLibraryPath [
                pkgs.stdenv.cc.cc.lib
                pkgs.zlib
                pkgs.portaudio
                pkgs.libsndfile
              ]
            }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            echo "BT dev shell. Run 'uv sync' once, then 'uv run bt' to start."
            echo "Ollama must be running separately (nixos: services.ollama.enable)."
          '';
        };
      }
    );
}
