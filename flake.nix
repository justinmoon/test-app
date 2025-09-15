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
          
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            nativeBuildInputs = with pkgs; [
              bun
            ];
            
            buildPhase = ''
              # No dependencies to install - we have a pure build!
              
              # Embed version in the source
              if [ -n "$GIT_COMMIT" ]; then
                echo "Embedding version: $GIT_COMMIT"
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
            '';
            
            installPhase = ''
              mkdir -p $out/test-app
              mkdir -p $out/bin
              
              # Copy only the source code (no deps needed!)
              cp -r src $out/test-app/
              
              # Create wrapper script that runs with bun
              cat > $out/bin/test-app <<EOF
              #!/usr/bin/env bash
              cd $out/test-app
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
            echo "Run 'bun run dev' to start the development server"
          '';
        };
      });
}