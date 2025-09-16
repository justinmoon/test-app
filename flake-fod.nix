{
  description = "Test app with proper Fixed-Output Derivation for dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Fixed-output derivation for dependencies
        # This is deterministic - same inputs always produce same output
        bunDeps = pkgs.stdenv.mkDerivation {
          pname = "test-app-deps";
          version = "1.0.0";
          
          src = ./.;
          
          nativeBuildInputs = [ pkgs.bun ];
          
          # Only copy files that affect dependencies
          buildPhase = ''
            # Copy only package.json and bun.lock
            cp ${./package.json} package.json
            cp ${./bun.lock} bun.lock
            
            # This will fetch dependencies from the network
            # But the output is verified against outputHash
            HOME=$TMPDIR bun install --frozen-lockfile --no-save
          '';
          
          installPhase = ''
            mkdir -p $out
            cp -r node_modules $out/
            # Also preserve the lock file for debugging
            cp bun.lock $out/
          '';
          
          # This is what makes it a FOD - network access allowed but output verified
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          # To get this hash:
          # 1. Set it to lib.fakeHash (or "")
          # 2. Build with: nix build .#test-app-deps
          # 3. Copy the hash from the error message
          # 4. Update this value
          outputHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Replace with actual
          
          # Important: these inputs affect when deps are refetched
          impureEnvVars = lib.fetchers.proxyImpureEnvVars;
        };
        
      in
      {
        packages = {
          default = self.packages.${system}.test-app;
          
          # Expose deps for testing/debugging
          deps = bunDeps;
          
          # Main app using the FOD dependencies
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = [ pkgs.bun ];
            
            buildPhase = ''
              # Copy source
              cp -r $src/src .
              cp $src/package.json .
              
              # Use pre-fetched dependencies (deterministic!)
              cp -r ${bunDeps}/node_modules .
              
              # Now build with dependencies available
              # This is pure - no network access needed
              
              # Embed version if provided
              if [ -n "$GIT_COMMIT" ]; then
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
            '';
            
            installPhase = ''
              mkdir -p $out/app $out/bin
              
              cp -r src $out/app/
              cp -r node_modules $out/app/
              cp package.json $out/app/
              
              cat > $out/bin/test-app <<EOF
              #!/usr/bin/env bash
              cd $out/app
              exec ${pkgs.bun}/bin/bun run src/index.ts "\$@"
              EOF
              chmod +x $out/bin/test-app
            '';
          };
        };
      });
}