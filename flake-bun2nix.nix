{
  description = "Test app using hypothetical bun2nix pattern";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Hypothetical - bun2nix doesn't exist yet but this is the pattern
    # Similar tools: npmlock2nix, yarn2nix, poetry2nix
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # This is how npmlock2nix works - it would parse bun.lock
        # and generate individual derivations for each dependency
        # Each package is fetched with its own hash
        bunPackages = pkgs.callPackage ./bun-packages.nix {
          # Generated from bun.lock
          # Each dependency becomes a fixed-output derivation
        };
        
        # Or using a hypothetical mkBunPackage helper
        mkBunPackage = { src, lockFile, ... }: pkgs.stdenv.mkDerivation {
          # This would:
          # 1. Parse bun.lock
          # 2. Create FOD for each dependency
          # 3. Assemble node_modules
          # 4. Build the package
        };
        
      in
      {
        packages = {
          default = self.packages.${system}.test-app;
          
          # Using the hypothetical helper
          test-app = mkBunPackage {
            pname = "test-app";
            version = "1.0.0";
            src = ./.;
            lockFile = ./bun.lock;
            
            # Build commands
            buildPhase = ''
              # Dependencies already available
              bun run build
            '';
          };
        };
      });
}