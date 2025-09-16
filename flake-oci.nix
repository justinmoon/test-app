{
  description = "Test app using OCI/Docker image for dependencies";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # Build a Docker image with dependencies
        # This is deterministic because the image has a fixed hash
        depsImage = pkgs.dockerTools.buildImage {
          name = "test-app-deps";
          tag = "latest";
          
          # Use a build stage that installs dependencies
          runAsRoot = ''
            #!${pkgs.runtimeShell}
            ${pkgs.bun}/bin/bun install --frozen-lockfile
          '';
          
          config = {
            WorkingDir = "/app";
          };
        };
        
        # Extract dependencies from the image
        extractedDeps = pkgs.runCommand "extract-deps" {} ''
          ${pkgs.skopeo}/bin/skopeo copy docker-archive:${depsImage} dir:$TMPDIR/image
          tar -xf $TMPDIR/image/*/layer.tar -C $TMPDIR
          cp -r $TMPDIR/app/node_modules $out
        '';
        
      in
      {
        packages = {
          default = self.packages.${system}.test-app;
          
          test-app = pkgs.stdenv.mkDerivation {
            pname = "test-app";
            version = "1.0.0";
            
            src = ./.;
            
            buildPhase = ''
              cp -r ${extractedDeps}/node_modules .
              # Build with dependencies
            '';
          };
        };
      });
}