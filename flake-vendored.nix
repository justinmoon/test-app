{
  description = "Test app with vendored dependencies approach";

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
          
          # For vendored approach, you'd run these commands locally:
          # bun install --frozen-lockfile
          # git add node_modules
          # git commit -m "Vendor dependencies"
          
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            # Source includes vendored node_modules
            src = ./.;
            
            nativeBuildInputs = [ pkgs.bun ];
            
            buildPhase = ''
              # Dependencies are already in source
              cp -r $src/* .
              chmod -R u+w .
              
              # Build steps here
              if [ -n "$GIT_COMMIT" ]; then
                sed -i "s/VERSION = process.env.GIT_COMMIT || \"dev\"/VERSION = \"$GIT_COMMIT\"/" src/index.ts
              fi
            '';
            
            installPhase = ''
              mkdir -p $out/app $out/bin
              
              cp -r src $out/app/
              cp -r node_modules $out/app/  # Vendored deps
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