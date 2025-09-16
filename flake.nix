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
          
          # Main package - assumes node_modules exists in build directory
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = with pkgs; [
              bun
            ];
            
            buildPhase = ''
              # Create directory structure
              mkdir -p src
              
              # Copy source files (excluding node_modules)
              cp $src/package.json .
              cp $src/bun.lock .
              cp -r $src/src/* src/
              
              # Check if node_modules exists (it should be created by CI before nix build)
              if [ -d "node_modules" ]; then
                echo "Found node_modules in working directory"
              elif [ -d "$src/node_modules" ]; then
                echo "Using node_modules from source"
                cp -r $src/node_modules .
              else
                echo "WARNING: node_modules not found, build may fail"
                echo "In CI, run 'bun install' before 'nix build'"
              fi
              
              # Embed version in the source
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
              if [ -d "node_modules" ]; then
                cp -r node_modules $out/app/
              fi
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
              description = "Test app for debugging GitHub runner permissions";
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
            echo "Run 'bun install' to install dependencies"
            echo "Run 'bun run dev' to start the development server"
          '';
        };
      });
}