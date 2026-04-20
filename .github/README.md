# template

[![check](https://img.shields.io/github/actions/workflow/status/spotdemo4/template/check.yaml?branch=main&logo=github&logoColor=%23bac2de&label=check&labelColor=%23313244)](https://github.com/spotdemo4/template/actions/workflows/check.yaml)
[![vulnerable](https://img.shields.io/github/actions/workflow/status/spotdemo4/template/vulnerable.yaml?branch=main&logo=github&logoColor=%23bac2de&label=vulnerable&labelColor=%23313244)](https://github.com/spotdemo4/template/actions/workflows/vulnerable.yaml)
[![nix](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Fspotdemo4%2Ftemplate%2Frefs%2Fheads%2Fmain%2Fflake.lock&query=%24.nodes.nixpkgs.original.ref&logo=nixos&logoColor=%23bac2de&label=channel&labelColor=%23313244&color=%234d6fb7)](https://nixos.org/)
[![flakehub](https://img.shields.io/endpoint?url=https://flakehub.com/f/spotdemo4/template/badge&labelColor=%23313244)](https://flakehub.com/flake/spotdemo4/template)

default template for projects

part of [spotdemo4/templates](https://github.com/spotdemo4/templates)

## requirements

- [nix](https://nixos.org/)

## getting started

```elm
nix develop
```

### check

```elm
nix flake check
```

### release

```elm
bumper
```

releases are automatically created for [significant](https://www.conventionalcommits.org/en/v1.0.0/#summary) changes
