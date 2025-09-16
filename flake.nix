{
  description = "Test app with deterministic dependency management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Fixed-output derivation for dependencies
        # This ensures deterministic, reproducible builds
        bunDeps = pkgs.stdenv.mkDerivation {
          pname = "test-app-deps";
          version = "1.0.0";
          
          # Only files that determine dependencies
          src = pkgs.runCommand "dep-src" {} ''
            mkdir -p $out
            cp ${./package.json} $out/package.json
            cp ${./bun.lock} $out/bun.lock
          '';
          
          nativeBuildInputs = [ pkgs.bun pkgs.cacert ];
          
          buildPhase = ''
            cp $src/* .
            
            # Set up environment for bun
            export HOME=$TMPDIR
            
            # Install with frozen lockfile - deterministic!
            bun install --frozen-lockfile --no-progress --no-summary
            
            # Remove cache to reduce output size
            rm -rf $HOME/.bun
          '';
          
          installPhase = ''
            mkdir -p $out
            cp -r node_modules $out/
            # Keep the lock file for reference
            cp bun.lock $out/
          '';
          
          # Fixed-output derivation settings
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          # This hash must be updated when dependencies change
          # To update: set to lib.fakeHash, build, copy hash from error
          outputHash = "sha256-BT9Ab+cjtfqxT4ETMGdd87J/me30DHlYlTOHsfVoTO4=";
        };
        
      in
      {
        packages = {
          default = self.packages.${system}.test-app;
          
          # Expose deps package for manual building/testing
          deps = bunDeps;
          
          # Main package - pure build using FOD dependencies
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = [ pkgs.bun ];
            
            buildPhase = ''
              # Copy source files
              mkdir -p src
              cp -r $src/src/* src/
              cp $src/package.json .
              cp $src/bun.lock .
              
              # Link pre-fetched dependencies (deterministic!)
              ln -s ${bunDeps}/node_modules node_modules
              
              # Verify dependencies are available
              test -d node_modules/uuid || (echo "Dependencies missing!" && exit 1)
              
              # Embed version
              if [ -n "$GIT_COMMIT" ]; then
                echo "Embedding version: $GIT_COMMIT"
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
              
              # For more complex builds (like slipbox), build steps here:
              # bun run build:client  # Would work with linked node_modules
            '';
            
            installPhase = ''
              mkdir -p $out/app $out/bin
              
              # Copy application files
              cp -r src $out/app/
              cp -r ${bunDeps}/node_modules $out/app/node_modules
              cp package.json $out/app/
              cp bun.lock $out/app/
              
              # Create executable wrapper
              cat > $out/bin/test-app <<EOF
              #!/usr/bin/env bash
              cd $out/app
              exec ${pkgs.bun}/bin/bun run src/index.ts "\$@"
              EOF
              chmod +x $out/bin/test-app
            '';
            
            meta = with pkgs.lib; {
              description = "Test app with deterministic dependencies";
              license = licenses.mit;
              platforms = platforms.all;
            };
          };
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            bun
            nodejs_20
          ];
          
          shellHook = ''
            echo "Test app development environment"
            echo "Commands:"
            echo "  bun install - Install dependencies locally"
            echo "  bun run dev - Start dev server"
            echo "  nix build .#deps - Build dependency FOD"
            echo "  nix build .#test-app - Build full app"
          '';
        };
      });
}