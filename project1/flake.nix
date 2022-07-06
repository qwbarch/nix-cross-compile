{
  description = "<DESCRIPTION-HERE>";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };


  outputs = { self, nixpkgs, haskellNix, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let projectName = "project1";
          compiler-nix-name = "ghc8107";
          index-state = "2022-07-05T00:00:00Z";

          mkProject = haskell-nix: haskell-nix.cabalProject' {
            src = ./.;
            inherit index-state compiler-nix-name;

            # plan-sha256 = "...";
            # materialized = ./materializations + "/${projectName}";
          };

          overlays = [
            haskellNix.overlay
            (self: super: { ${projectName} = mkProject self.haskell-nix; })
          ];

          pkgs = import nixpkgs { inherit system overlays; };
          project = pkgs.${projectName};
          flake = pkgs.${projectName}.flake {
            crossPlatforms = p: with p; [ mingwW64 ];
          };

          tools = {
            haskell-language-server = {
              inherit index-state;
              # plan-sha256 = "...";
              # materialized = ./materializations/haskell-language-server;
            };

            hoogle = {
              inherit index-state;
              # plan-sha256 = "...";
              # materialized = ./materializations/hoogle;
            };
          };

          devShell = project.shellFor {
            packages = ps: [ ps.${projectName} ];
            exactDeps = true;
            inherit tools;
          };

      in flake // {
        inherit overlays devShell;
        nixpkgs = pkgs;

        defaultPackage = flake.packages."${projectName}:exe:${projectName}";

        packages = flake.packages // {
          gcroot = pkgs.linkFarmFromDrvs "${projectName}-shell-gcroot" [
            devShell
            devShell.stdenv
            project.plan-nix
            project.roots

            (
              let compose = f: g: x: f (g x);
                  flakePaths = compose pkgs.lib.attrValues (
                    pkgs.lib.mapAttrs
                      (name: flake: { name = name; path = flake.outPath; })
                  );
              in  pkgs.linkFarm "input-flakes" (flakePaths self.inputs)
            )

            (
              let getMaterializers = ( name: project:
                    pkgs.linkFarmFromDrvs "${name}" [
                      project.plan-nix.passthru.calculateMaterializedSha
                      project.plan-nix.passthru.generateMaterialized
                    ]
                  );
              in
                pkgs.linkFarmFromDrvs "materializers" (
                  pkgs.lib.mapAttrsToList getMaterializers (
                      { ${projectName} = project; }
                      // (pkgs.lib.mapAttrs (_: builtins.getAttr "project") (project.tools tools))
                  )
                )
            )
          ];
        };
      }
    );
}