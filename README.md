# edge-grid-puzzle-solvers-modeling

Julia and LaTeX project for modeling and comparing exact and heuristic solvers for grid-based puzzle families in the ENSTA course project.

## Table of contents

- [Links](#links)
- [Repository layout](#repository-layout)
- [Requirements](#requirements)
- [Julia environments](#julia-environments)
- [Quick start](#quick-start)
- [Palisade workflow](#palisade-workflow)
- [Notes for contributors](#notes-for-contributors)

## Links

- Project site: <https://javiertarazona06.github.io/edge-grid-puzzle-solvers-modeling/>

There you can find the report of the project.

## Repository layout

- `sudoku1.0/`: most complete Julia implementation example in the repository. It includes dataset generation, CPLEX-based solving, heuristic solvers, a callback-based variant, and utilities to export result tables and plots.
- `loopy/`: project scaffold for the Loopy puzzle family.
- `palisade/`: Julia implementation for the Palisade puzzle family
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

## Palisade workflow

Run Palisade commands from `palisade/src`, because the project paths are written relative to that directory.

### 1. Start Julia

From the repository root:

```bash
cd palisade
julia --project=.
```

Inside Julia:

```julia
using Pkg
Pkg.instantiate()
cd("src")
```

From that point, all examples below assume you are still inside `palisade/src`.

### 2. Read one instance

Load the input/output utilities and read the fixed test instance:

```julia
include("io.jl")
t = readInputFile("../data/instanceTest.txt")
```

`readInputFile()` reads a text grid from `palisade/data/` and returns it as a matrix, using `-1` for empty cells.

### 3. Display an unresolved instance and a solved instance

To show the unresolved puzzle in the terminal:

```julia
displayGrid(t)
```

To show a solved puzzle, you first need a CPLEX solution because `displaySolution()` uses the wall variables `yh` and `yv`:

```julia
include("resolution.jl")
isOptimal, x, yh, yv, solveTime = cplexSolve(t)
displaySolution(t, yh, yv)
```

This is the workflow used for the console screenshots shown in the report.

### 4. Generate one random instance

Load the generator and create one random Palisade grid:

```julia
include("generation.jl")
grid = generateInstance(6, 6, 9, 0.6)
displayGrid(grid)
```

Arguments:

- `n`, `m`: board dimensions
- `k`: number of regions
- `fillRatio`: fraction of clues kept visible

Important condition: the board area `n * m` must be divisible by `k`.

### 5. Generate a dataset in `palisade/data/`

To generate several instances and write them to disk:

```julia
include("generation.jl")
generateDataSet(2, 6, 6, 9, 0.6)
```

This creates files such as:

```text
palisade/data/gen_6x6_reg9_1.txt
palisade/data/gen_6x6_reg9_2.txt
```

The generated instances are written to `palisade/data/`. Existing files with the same name are not regenerated.

### 6. Solve one instance with CPLEX

To solve one instance with the exact model and the connectivity callback:

```julia
include("resolution.jl")
t = readInputFile("../data/instanceTest.txt")
isOptimal, x, yh, yv, solveTime = cplexSolve(t)
```

The function `cplexSolve` accepts optional keyword arguments to define the region structure and the time limit:

- `regionSize`: number of cells in each region. The value must divide `nbRows * nbCols`.
- `nbRegions`: number of regions. This is useful for generated instances named with `reg...`.
- `timeLimit=100.0`: maximum CPLEX resolution time in seconds.

Pass either `regionSize` or `nbRegions` when the default case does not match the instance. For example, to use another region size:

```julia
isOptimal, x, yh, yv, solveTime = cplexSolve(t; regionSize=4)
```

For generated instances whose region count is known from the filename, you can pass the number of regions explicitly:

```julia
t = readInputFile("../data/gen_6x6_reg9_1.txt")
isOptimal, x, yh, yv, solveTime = cplexSolve(t; nbRegions=9)
```

You can also run steps 1 to 5 in one command and keep the variables available in the Julia session:

```bash
cd palisade && julia --project=. -i -e 'using Pkg; Pkg.instantiate(); cd("src"); include("io.jl"); include("resolution.jl"); global t = readInputFile("../data/instanceTest.txt"); global isOptimal, x, yh, yv, solveTime = cplexSolve(t; regionSize=5)'
```

Display the main result values:

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

To check explicitly that the callback returned connected regions, run:

```julia
checkConnectedRegions(t, x)
```

If you solved the instance with a non-default region size, use the same value here:

```julia
checkConnectedRegions(t, x; regionSize=5)
```

This requires a working local CPLEX installation and license.

### 7. Solve one instance with the heuristic

To run the heuristic solver on one instance:

```julia
include("resolution.jl")
t = readInputFile("../data/gen_6x6_reg9_1.txt")
isOptimal, solvedGrid, solveTime = heuristicSolve(t; nbRegions=9)
```

The heuristic returns:

- `isOptimal`: whether a valid solution was found before the time limit
- `solvedGrid`: the region assignment found by the search
- `solveTime`: elapsed resolution time

### 8. Solve all instances in `palisade/data/`

To run both methods on every `.txt` instance stored in `palisade/data/`:

```julia
include("resolution.jl")
solveDataSet()
```

Useful variants:

```julia
solveDataSet(methods="cplex")
solveDataSet(methods="heuristic")
solveDataSet(methods="heuristique")
solveDataSet(timeLimit=100.0)
```

How it works:

- it reads every instance from `palisade/data/`
- it solves each instance with the selected method(s)
- it writes one result file per instance

Output folders:

- `palisade/res/cplex/`
- `palisade/res/heuristic/`

Each result file contains at least:

```text
solveTime = ...
isOptimal = ...
```

The files also store:

```text
regionSize = ...
```

If a result file already exists with the same `regionSize`, `solveDataSet()` does not recompute that instance.

### 9. Export result tables and a performance diagram

The professor-provided functions are in `io.jl`.

Generate a LaTeX table with all current results:

```julia
include("io.jl")
resultsArray("../res/results_array.tex")
```

Generate a PDF performance diagram from the `res/` folders:

```julia
performanceDiagram("../res/performance_diagram.pdf")
```

If you want to restrict the benchmark to generated instances only and exclude `instanceTest.txt`:

```julia
resultsArray("../res/results_array_generated.tex"; generatedOnly=true)
performanceDiagram("../res/performance_diagram_generated.pdf"; generatedOnly=true)
```

### 10. Regenerate the Palisade report artifacts

The small analysis pipeline used for the report can be rerun with:

```bash
cd palisade
julia --project=. src/analysis_results.jl
```

This regenerates the Palisade tables and figures used in `docs/rapport/`.