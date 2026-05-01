# edge-grid-puzzle-solvers-modeling

Julia and LaTeX project for modeling and comparing exact and heuristic solvers for grid-based puzzle families in the ENSTA course project.

## Table of contents

- [Links](#links)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Julia environments](#julia-environments)
- [Quick start](#quick-start)
- [Run Julia for Palisade](#run-julia-for-palisade)
- [Notes for contributors](#notes-for-contributors)

## Links

- Project site: <https://javiertarazona06.github.io/edge-grid-puzzle-solvers-modeling/>

There you can find the report of the project.

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
- Building the report requires a LaTeX distribution capable of compiling `docs/rapport/rapport.tex`.

## Julia environments

The repository now includes Julia environments:

- a root environment in `./Project.toml`
- a dedicated environment in `palisade/Project.toml`
- a dedicated environment in `loopy/Project.toml`
- a dedicated environment in `sudoku1.0/Project.toml`

To install the dependencies of one environment, activate it and instantiate it.

Example for the `palisade/` project:

```bash
cd palisade
julia --project=.
```

Inside the Julia REPL:

```julia
using Pkg
Pkg.instantiate()
```

You can do the same in `loopy/`, `sudoku1.0/`, or at the repository root depending on which environment you want to use.

## Quick start

### Sudoku workflow

The `sudoku1.0/` folder is the best entry point if you want to run the existing code.

```bash
cd sudoku1.0
julia --project=.
```

Inside the Julia REPL:

```julia
using Pkg
Pkg.instantiate()
cd("src")
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

## Run Julia for Palisade

Run Julia commands for the Palisade project from the `palisade/src` directory, because file paths in the current scaffold are written relative to that location.

### Run Tests Fixed Instance

To test `readInputFile` in `palisade/src/io.jl` with the instance file `palisade/data/instanceTest.txt`:

1. Go to the `palisade` directory:

```bash
cd palisade
```

2. Start Julia with the Palisade environment:

```bash
julia --project=.
```

3. Instantiate the environment if you have not done it yet:

```julia
using Pkg
Pkg.instantiate()
```

4. Go to the `src` directory inside Julia:

```julia
cd("src")
```

5. Load the file:

```julia
include("io.jl")
```

6. Run the input-reading function:

```julia
readInputFile("../data/instanceTest.txt")
```

You can also run the same test in one shell command:

```bash
cd palisade
julia --project=. -e 'using Pkg; Pkg.instantiate(); cd("src"); include("io.jl"); readInputFile("../data/instanceTest.txt")'
```

### Run CPLEX on Fixed Instance

To run `cplexSolve(t::Matrix{Int64})` from `palisade/src/resolution.jl` on `palisade/data/instanceTest.txt`:

1. Go to the `palisade` directory:

```bash
cd palisade
```

2. Start Julia with the Palisade environment:

```bash
julia --project=.
```

3. Instantiate the environment if needed:

```julia
using Pkg
Pkg.instantiate()
```

4. Go to the `src` directory inside Julia:

```julia
cd("src")
```

5. Load the files and solve the fixed instance:

```julia
include("io.jl")
include("resolution.jl")
t = readInputFile("../data/instanceTest.txt")
isOptimal, x, yh, yv, solveTime = cplexSolve(t)
```

You can also run steps 1 to 5 in one command and keep the variables available in the Julia session:

```bash
cd palisade && julia --project=. -i -e 'using Pkg; Pkg.instantiate(); cd("src"); include("io.jl"); include("resolution.jl"); global t = readInputFile("../data/instanceTest.txt"); global isOptimal, x, yh, yv, solveTime = cplexSolve(t)'
```

6. Display the main result values:

```julia
println("isOptimal = ", isOptimal)
println("solveTime = ", solveTime)
println("yh = ")
println(JuMP.value.(yh))
println("yv = ")
println(JuMP.value.(yv))
```

You can also inspect the region-assignment variables:

```julia
println("x[:,:,1] = ")
println(JuMP.value.(x[:, :, 1]))
```

This requires a working local CPLEX installation and license.

The same activation pattern applies to `loopy/` and `sudoku1.0/`.

## Notes for contributors

- Activate the matching Julia environment before running code from `palisade/`, `loopy/`, or `sudoku1.0/`.
- Run Julia scripts from each puzzle's `src/` directory because paths are written relative to that location.
- Result folders such as `res/` contain generated artifacts rather than hand-written source files.
- Editor backup files and generated result folders are partially covered by `.gitignore`.
