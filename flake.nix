{
  description = "Test app for debugging NixOS GitHub runner permissions";

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
        packages = {
          default = self.packages.${system}.test-app;
          
          # Main package - bundles everything into a single executable
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = with pkgs; [
              bun
            ];
            
            # Disable sandbox for this specific derivation to allow network access
            # This is needed for bun install to work
            __noChroot = true;
            
            buildPhase = ''
              # Copy source files
              cp -r $src/* .
              chmod -R u+w .
              
              # Install dependencies (requires network access)
              export HOME=$TMPDIR
              bun install --frozen-lockfile
              
              # Embed version in the source
              if [ -n "$GIT_COMMIT" ]; then
                echo "Embedding version: $GIT_COMMIT"
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
              
              # Bundle the application with all dependencies into a single executable
              echo "Building standalone executable..."
              bun build src/index.ts --compile --outfile test-app-bundled --target=bun-linux-x64
            '';
            
            installPhase = ''
              mkdir -p $out/bin
              cp test-app-bundled $out/bin/test-app
              chmod +x $out/bin/test-app
            '';
            
            meta = with pkgs.lib; {
              description = "Test app for debugging GitHub runner permissions";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          };
          
          # Alternative: runtime version (requires bun to run)
          test-app-runtime = pkgs.stdenv.mkDerivation {
            pname = "test-app-runtime";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = with pkgs; [
              bun
            ];
            
            __noChroot = true;
            
            buildPhase = ''
              # Copy source files
              cp -r $src/* .
              chmod -R u+w .
              
              # Install dependencies
              export HOME=$TMPDIR
              bun install --frozen-lockfile
              
              # Embed version
              if [ -n "$GIT_COMMIT" ]; then
                echo "Embedding version: $GIT_COMMIT"
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
            '';
            
            installPhase = ''
              mkdir -p $out/app
              mkdir -p $out/bin
              
              # Copy everything needed to run
              cp -r src $out/app/
              cp -r node_modules $out/app/
              cp package.json $out/app/
              cp bun.lock $out/app/
              
              # Create wrapper script
              cat > $out/bin/test-app <<EOF
              #!/usr/bin/env bash
              cd $out/app
              exec ${pkgs.bun}/bin/bun run src/index.ts "\$@"
              EOF
              chmod +x $out/bin/test-app
            '';
            
            meta = with pkgs.lib; {
              description = "Test app runtime version";
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
            echo "Run 'bun run dev' to start the development server"
          '';
        };
      });
}