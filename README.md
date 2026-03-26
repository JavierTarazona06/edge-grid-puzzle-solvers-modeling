# edge-grid-puzzle-solvers-modeling

Julia and LaTeX project for modeling and comparing exact and heuristic solvers for grid-based puzzle families in the ENSTA course project.

## Links

- Report PDF: <https://javiertarazona06.github.io/edge-grid-puzzle-solvers-modeling/rapport.pdf>
- Project site: <https://javiertarazona06.github.io/edge-grid-puzzle-solvers-modeling/>

## Repository layout

- `sudoku1.0/`: most complete Julia implementation example in the repository. It includes dataset generation, CPLEX-based solving, heuristic solvers, a callback-based variant, and utilities to export result tables and plots.
- `loopy/`: project scaffold for the Loopy puzzle family. The directory structure is in place, but several core methods still contain `TODO` markers.
- `palisade/`: project scaffold for the Palisade puzzle family. Like `loopy/`, it is currently a template with unfinished generation and solving logic.
- `docs/rapport/`: LaTeX sources for the written report compiled by GitHub Actions.
- `.github/workflows/latex.yml`: CI workflow that builds the report PDF and publishes it to GitHub Pages on pushes to `main`.

## Requirements

The Julia code relies on these packages:

- `JuMP`
- `CPLEX`
- `Plots`
- `GR`

Additional notes:

- `CPLEX` requires a local IBM CPLEX installation and a valid license.
- The repository currently does not include a `Project.toml` or `Manifest.toml`, so dependencies must be installed in your Julia environment manually.
- Building the report requires a LaTeX distribution capable of compiling `docs/rapport/rapport.tex`.

## Quick start

### Sudoku workflow

The `sudoku1.0/` folder is the best entry point if you want to run the existing code.

```bash
cd sudoku1.0/src
julia
```

Inside the Julia REPL:

```julia
include("generation.jl")
generateDataSet()
```

```julia
include("resolution.jl")
solveDataSet()
```

```julia
include("io.jl")
resultsArray("../res/array.tex")
performanceDiagram("../res/array.pdf")
```

Generated input instances are written to `sudoku1.0/data/`, and solver outputs are written to subdirectories inside `sudoku1.0/res/`.

### Report build

To compile the report locally:

```bash
cd docs/rapport
latexmk -pdf rapport.tex
```

On GitHub, the workflow in `.github/workflows/latex.yml` automatically builds `docs/rapport/rapport.pdf` and publishes it through GitHub Pages.

## Current project status

- `sudoku1.0/` contains working code and sample data/results.
- `loopy/` and `palisade/` are not yet feature-complete and should be treated as work-in-progress templates.
- The report source exists, but the main document is still fairly minimal and appears to be under active development.

## Notes for contributors

- Run Julia scripts from each puzzle's `src/` directory because paths are written relative to that location.
- Result folders such as `res/` contain generated artifacts rather than hand-written source files.
- Editor backup files and generated result folders are partially covered by `.gitignore`, but dependency management has not yet been formalized with a Julia project environment.
