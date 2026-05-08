# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX                                 # IBM's Mathematical Optimization Solver
using JuMP                                  # Julia's package for Mathematical Optimization
import MathOptInterface as MOI              # Low Level interface of JUMP, used for CPLEX callbacks

include("generation.jl")

TOL = 0.00001                               # Tolerance for numerical issues in the callback

"""
Resolve the common region size from either the size of each region or the
number of regions.
"""
function resolveRegionSize(t::AbstractMatrix{<:Integer};
                           regionSize::Union{Nothing,Int}=nothing,
                           nbRegions::Union{Nothing,Int}=nothing,
                           defaultRegionSize::Union{Nothing,Int}=5)
    nbRows, nbCols = size(t)
    area = nbRows * nbCols

    if regionSize === nothing && nbRegions === nothing
        if defaultRegionSize === nothing
            error("Missing region information. Pass either regionSize or nbRegions.")
        end
        regionSize = defaultRegionSize
    end

    if regionSize !== nothing
        if regionSize <= 0
            error("regionSize must be positive.")
        end
        if area % regionSize != 0
            error("regionSize must divide the board area.")
        end
    end

    if nbRegions !== nothing
        if nbRegions <= 0
            error("nbRegions must be positive.")
        end
        if area % nbRegions != 0
            error("nbRegions must divide the board area.")
        end

        inferredRegionSize = div(area, nbRegions)
        if regionSize !== nothing && regionSize != inferredRegionSize
            error("regionSize and nbRegions are inconsistent with the board area.")
        end
        regionSize = inferredRegionSize
    end

    return regionSize
end

function resultRegionSize(resultFile::String)
    if !isfile(resultFile)
        return nothing
    end

    for line in eachline(resultFile)
        strippedLine = strip(line)
        if startswith(strippedLine, "regionSize")
            return parse(Int, strip(split(strippedLine, "=", limit=2)[2]))
        end
    end

    return nothing
end

"""
Solve an instance with CPLEX.
"""
function cplexSolve(t::Matrix{Int64};
                    regionSize::Union{Nothing,Int}=nothing,
                    nbRegions::Union{Nothing,Int}=nothing,
                    timeLimit=100.0,
                    printValues::Bool=false)
    """
        t : Game cells
        regionSize : Number of cells in each region.
        nbRegions : Number of regions. If provided, regionSize is inferred.
        timeLimit : CPLEX time limit in seconds.
        printValues : If true, the returned values are printed.
    """

    nbRows = size(t, 1)                                      # Get number of rows. Indexed with 1
    nbCols = size(t, 2)                                      # Get number of columns. Indexed with 2

    regionSize = resolveRegionSize(t; regionSize=regionSize, nbRegions=nbRegions)
    nbRegions = div(nbRows * nbCols, regionSize)              # Get number of regions

    # Create the model
    m = Model(CPLEX.Optimizer)

    # -----------------------------
    # Variables
    # -----------------------------

    # Cell-to-region assignment - x[row, col, region] - Binary variable
    @variable(m, x[1:nbRows, 1:nbCols, 1:nbRegions], Bin)

    # Palisades between vertically adjacent cells
    @variable(m, yh[1:nbRows-1, 1:nbCols], Bin)

    # Palisades between horizontally adjacent cells
    @variable(m, yv[1:nbRows, 1:nbCols-1], Bin)

    # Auxiliary variables for pairs of vertically adjacent cells
    @variable(m, zh[1:nbRows-1, 1:nbCols, 1:nbRegions], Bin)

    # Auxiliary variables for pairs of horizontally adjacent cells
    @variable(m, zv[1:nbRows, 1:nbCols-1, 1:nbRegions], Bin)

    # -----------------------------
    # Function objective
    # -----------------------------

    # Feasibility problem
    @objective(m, Min, 0)

    # -----------------------------
    # Constraints
    # -----------------------------

    # Each cell belongs to exactly one region
    for i in 1:nbRows
        for j in 1:nbCols
            @constraint(m, sum(x[i, j, p] for p in 1:nbRegions) == 1)
        end
    end

    # Each region contains exactly regionSize cells
    for p in 1:nbRegions
        @constraint(m, sum(x[i, j, p] for i in 1:nbRows, j in 1:nbCols) == regionSize)
    end


    # Linearization and belonging of neighboring cells to the same region

        # 1. Linearization on vertically adjacent cells
    for i in 1:nbRows-1
        for j in 1:nbCols
            for p in 1:nbRegions
                @constraint(m, zh[i, j, p] <= x[i, j, p])
                @constraint(m, zh[i, j, p] <= x[i+1, j, p])
                @constraint(m, zh[i, j, p] >= x[i, j, p] + x[i+1, j, p] - 1)
            end
        end
    end

        # 2. Linearization on horizontally adjacent cells
    for i in 1:nbRows
        for j in 1:nbCols-1
            for p in 1:nbRegions
                @constraint(m, zv[i, j, p] <= x[i, j, p])
                @constraint(m, zv[i, j, p] <= x[i, j+1, p])
                @constraint(m, zv[i, j, p] >= x[i, j, p] + x[i, j+1, p] - 1)
            end
        end
    end

    # Palisade definition

        # 1. Vertically
    for i in 1:nbRows-1
        for j in 1:nbCols
            @constraint(m, yh[i, j] + sum(zh[i, j, p] for p in 1:nbRegions) == 1)
        end
    end

        # 2. Horizontally
    for i in 1:nbRows
        for j in 1:nbCols-1
            @constraint(m, yv[i, j] + sum(zv[i, j, p] for p in 1:nbRegions) == 1)
        end
    end

    # Constraints on numbered cells
    for i in 1:nbRows
        for j in 1:nbCols
            if t[i, j] != -1
                borderCount = 0

                # Count the borders of the grid that are adjacent to the cell (i, j)
                if i == 1
                    borderCount += 1                    # Top Border grid
                end
                if i == nbRows
                    borderCount += 1                    # Bottom Border grid
                end
                if j == 1
                    borderCount += 1                    # Left Border grid
                end
                if j == nbCols
                    borderCount += 1                    # Right Border grid
                end

                expr = borderCount

                # Add the palisades adjacent to the cell (i, j). Not borders of the grid.
                if i > 1
                    expr += yh[i-1, j] # Up cell border. Not grid
                end
                if i < nbRows
                    expr += yh[i, j] # Beneath cell border. Not grid
                end
                if j > 1
                    expr += yv[i, j-1] # Left cell border. Not grid
                end
                if j < nbCols
                    expr += yv[i, j] # Right cell border. Not grid
                end

                @constraint(m, expr == t[i, j])
            end
        end
    end

    function callback_connectivity(cb_data::CPLEX.CallbackContext, context_id::Clong)
        """
        Callback function to compute the connectivity of the palisades.

            cb_data : CPLEX callback context to inspect data and Constraints
            context_id : CPLEX callback context identifier to access or not
                Other contexts are threads, relaxation solution, branching...
        """

        if isIntegerPoint(cb_data, context_id)

            # JUMP loads the current solution values for de cb context
            CPLEX.load_callback_variable_primal(cb_data, context_id)

            # Array of cell in a region variables got from cb context
            x_val = callback_value.(cb_data, x)

            for p in 1:nbRegions

                #  Get cells from current region
                    # 0.9 and not ==1 used for tolerance protection
                cells = [(i, j) for i in 1:nbRows, j in 1:nbCols if x_val[i, j, p] > 0.9]

                # Get the connected components of the region
                components = connectedComponents(cells, nbRows, nbCols)

                if length(components) > 1
                    # The region is not well formed
                    for W in components
                        Wset = Set(W)
                        
                        # List to store zh and zv variables to check connectivity
                        borderTerms = Any[]

                        for (i, j) in W
                            # Only if neighbors are not in the Wset
                            
                            if i > 1 && !((i-1, j) in Wset)
                                push!(borderTerms, zh[i-1, j, p])  # Get value if upper cell is also at region p
                            end

                            if i < nbRows && !((i+1, j) in Wset)
                                push!(borderTerms, zh[i, j, p])  # Get value if cell beneath is also at region p
                            end

                            if j > 1 && !((i, j-1) in Wset)
                                push!(borderTerms, zv[i, j-1, p])  # Get value if left cell is also at region p
                            end

                            if j < nbCols && !((i, j+1) in Wset)
                                push!(borderTerms, zv[i, j, p])  # Get value if right cell is also at region p
                            end
                        end

                        # Sum of cell of W that belong to the region p
                        leftSide = sum(x[i, j, p] for (i, j) in W)
                        # Number of cells in W - 1, to block that component and make model to look for another solution
                        rightSide = length(W) - 1

                        # In the component there is a cell that can connects to cell not in the 
                            # current component, but at the same region. So that makes possible to re-use that 
                            # component as it is valid
                        if length(borderTerms) > 0
                            rightSide += sum(borderTerms)
                        end

                        # Constrain addition to the model
                        cstr = @build_constraint(leftSide <= rightSide)
                        # Adding lazy constraint to the call back
                        MOI.submit(m, MOI.LazyConstraint(cb_data), cstr)
                    end
                end
            end
        end
    end

    # CPLEX callbacks are used with one thread.
    MOI.set(m, MOI.NumberOfThreads(), 1)
    # Data limit fixed
    MOI.set(m, MOI.TimeLimitSec(), timeLimit)
    # Registers the funciton callback_connectivity as the CPLEX Callback
    MOI.set(m, CPLEX.CallbackFunction(), callback_connectivity)

    # Start a chronometer
    start = time()

    # Solve the model
    optimize!(m)

    isOptimal = JuMP.is_solved_and_feasible(m)
    solveTime = time() - start

    if printValues
        println("isOptimal is ", isOptimal)
        println("x is ", JuMP.value.(x))
        println("yh is ", JuMP.value.(yh))
        println("yv is ", JuMP.value.(yv))
        println("solveTime is ", solveTime)
    end

    # Return:
    # 1 - true if an optimum is found
    # 2 - the resolution time
    return isOptimal, x, yh, yv, solveTime
    
end

"""
Check that all regions returned by cplexSolve are connected.
"""
function checkConnectedRegions(t::Matrix{Int64}, x; regionSize::Int64=5)
    """
    Post-solve check to confirm that each region has one exactly connected component
    """

    vals = JuMP.value.(x)
    nbRows, nbCols = size(t)
    nbRegions = div(nbRows * nbCols, regionSize)

    connected = all(
        length(
            connectedComponents(
                [(i, j) for i in 1:nbRows, j in 1:nbCols if vals[i, j, p] > 0.9],
                nbRows,
                nbCols,
            ),
        ) == 1 for p in 1:nbRegions
    )

    println("connected = ", connected)

    return connected
end

"""
Heuristically solve an instance
"""
function isValidMove(grid::Matrix{Int}, clues::Matrix{Int}, row::Int, col::Int, regionId::Int, regionSize::Int)
    n, m = size(grid)

    if count(==(regionId), grid) >= regionSize
        return false
    end

    grid[row, col] = regionId
    isValid = true

    cellsToCheck = [(row, col), (row-1, col), (row+1, col), (row, col-1), (row, col+1)]

    for (i, j) in cellsToCheck
        if 1 <= i <= n && 1 <= j <= m && clues[i, j] != -1
            if grid[i, j] != 0
                confirmedWalls = 0
                potentialWalls = 0

                for (rowDelta, colDelta) in [(-1,0), (1,0), (0,-1), (0,1)]
                    nextRow, nextCol = i + rowDelta, j + colDelta

                    if nextRow < 1 || nextRow > n || nextCol < 1 || nextCol > m
                        confirmedWalls += 1
                        potentialWalls += 1
                    else
                        if grid[nextRow, nextCol] == 0
                            potentialWalls += 1
                        elseif grid[nextRow, nextCol] != grid[i, j]
                            confirmedWalls += 1
                            potentialWalls += 1
                        end
                    end
                end

                if confirmedWalls > clues[i, j]
                    isValid = false
                    break
                end

                if potentialWalls < clues[i, j]
                    isValid = false
                    break
                end
            end
        end
    end

    grid[row, col] = 0

    return isValid
end

"""
Check that each region forms one connected component of the expected size.
"""
function checkConnectivity(grid::Matrix{Int}, n::Int, m::Int, k::Int, regionSize::Int)
    visited = falses(n, m)

    for regionId in 1:k
        startRow, startCol = 0, 0
        for i in 1:n, j in 1:m
            if grid[i, j] == regionId
                startRow, startCol = i, j
                break
            end
        end

        if startRow == 0 return false end

        queue = [(startRow, startCol)]
        visited[startRow, startCol] = true
        count = 0

        while !isempty(queue)
            currentRow, currentCol = popfirst!(queue)
            count += 1

            for (rowDelta, colDelta) in [(-1,0), (1,0), (0,-1), (0,1)]
                nextRow, nextCol = currentRow + rowDelta, currentCol + colDelta
                if 1 <= nextRow <= n && 1 <= nextCol <= m && !visited[nextRow, nextCol] && grid[nextRow, nextCol] == regionId
                    visited[nextRow, nextCol] = true
                    push!(queue, (nextRow, nextCol))
                end
            end
        end

        if count != regionSize
            return false
        end
    end
    return true
end

"""
Recursive engine that iterates through the board trying to fill it.
"""
function backtrackSolve!(grid::Matrix{Int}, clues::Matrix{Int}, n::Int, m::Int, k::Int, regionSize::Int, row::Int, col::Int, deadline=Inf)
    if time() >= deadline
        return nothing
    end

    if col > m
        row += 1
        col = 1
    end

    if row > n
        return checkConnectivity(grid, n, m, k, regionSize)
    end

    if grid[row, col] != 0
        return backtrackSolve!(grid, clues, n, m, k, regionSize, row, col + 1, deadline)
    end

    for regionId in 1:k
        if isValidMove(grid, clues, row, col, regionId, regionSize)

            grid[row, col] = regionId

            result = backtrackSolve!(grid, clues, n, m, k, regionSize, row, col + 1, deadline)
            if result === nothing
                grid[row, col] = 0
                return nothing
            end
            if result
                return true
            end

            grid[row, col] = 0
        end
    end

    return false
end

"""
Solve a Palisade puzzle with backtracking and pruning.
"""
function heuristicSolve(clues::Matrix{Int};
                        regionSize::Union{Nothing,Int}=nothing,
                        nbRegions::Union{Nothing,Int}=nothing,
                        timeLimit=100.0)
    startTime = time()
    n, m = size(clues)
    regionSize = resolveRegionSize(clues; regionSize=regionSize, nbRegions=nbRegions)
    deadline = startTime + timeLimit

    k = div(n * m, regionSize)
    grid = zeros(Int, n, m)

    result = backtrackSolve!(grid, clues, n, m, k, regionSize, 1, 1, deadline)
    isSolved = result === true

    solveTime = time() - startTime
    return isSolved, grid, solveTime
end

"""
Infer the region size from generated file names such as gen_8x6_reg8_1.txt.
Fallback instances keep the Palisade default region size 5.
"""
function inferRegionSize(file::String, t::Matrix{Int64};
                         regionSize::Union{Nothing,Int}=nothing,
                         nbRegions::Union{Nothing,Int}=nothing,
                         defaultRegionSize::Union{Nothing,Int}=5)
    if regionSize !== nothing || nbRegions !== nothing
        return resolveRegionSize(t; regionSize=regionSize, nbRegions=nbRegions)
    end

    patternMatch = match(r"^gen_(\d+)x(\d+)_reg(\d+)_\d+\.txt$", basename(file))

    if patternMatch === nothing
        return resolveRegionSize(t; defaultRegionSize=defaultRegionSize)
    end

    nbRows = parse(Int, patternMatch.captures[1])
    nbCols = parse(Int, patternMatch.captures[2])
    nbRegions = parse(Int, patternMatch.captures[3])

    if size(t) != (nbRows, nbCols)
        error("Instance filename dimensions do not match file contents: $file")
    end
    return resolveRegionSize(t; nbRegions=nbRegions, defaultRegionSize=defaultRegionSize)
end

function selectedResolutionMethods(methods)
    availableMethods = Dict(
        "cplex" => ("cplex", "cplex"),
        "heuristic" => ("heuristic", "heuristic"),
        "heuristique" => ("heuristic", "heuristic"),
    )

    methodNames = methods isa Union{AbstractString,Symbol} ? [methods] : collect(methods)
    selectedMethods = Tuple{String,String}[]

    for method in methodNames
        methodKey = lowercase(String(method))
        if !haskey(availableMethods, methodKey)
            error("Unknown resolution method: $method. Use \"cplex\" or \"heuristic\".")
        end

        selectedMethod = availableMethods[methodKey]
        if !(selectedMethod in selectedMethods)
            push!(selectedMethods, selectedMethod)
        end
    end

    return selectedMethods
end

"""
Solve all the instances contained in "../data" with the selected methods.

The results are written in "../res/cplex" and "../res/heuristic"

Remark: If an instance has previously been solved with the same region size
(either by cplex or the heuristic) it will not be solved again.
"""
function solveDataSet(; methods=("cplex", "heuristic"),
                        regionSize::Union{Nothing,Int}=nothing,
                        nbRegions::Union{Nothing,Int}=nothing,
                        defaultRegionSize::Union{Nothing,Int}=5,
                        timeLimit=100.0)

    dataFolder = joinpath(@__DIR__, "..", "data")
    resFolder = joinpath(@__DIR__, "..", "res")

    # Each pair contains the output folder name and the method label to display.
    resolutionMethods = selectedResolutionMethods(methods)

    # Array which contains the result folder of each resolution method
    resolutionFolders = [joinpath(resFolder, methodFolder) for (methodFolder, _) in resolutionMethods]

    # Create each result folder if it does not exist
    for folder in resolutionFolders
        mkpath(folder)
    end

    global isOptimal = false
    global solveTime = -1

    instanceFiles = filter(x -> endswith(x, ".txt"), readdir(dataFolder))

    if isempty(instanceFiles)
        println("No instances found in: ", dataFolder)
        return
    end

    # For each instance
    for file in instanceFiles

        println("-- Resolution of ", file)
        t = readInputFile(joinpath(dataFolder, file))
        instanceRegionSize = inferRegionSize(file, t;
                                             regionSize=regionSize,
                                             nbRegions=nbRegions,
                                             defaultRegionSize=defaultRegionSize)

        # For each resolution method
        for methodId in eachindex(resolutionMethods)
            methodFolder, methodLabel = resolutionMethods[methodId]

            outputFile = joinpath(resolutionFolders[methodId], file)

            # If the instance has not already been solved by this method
            if resultRegionSize(outputFile) != instanceRegionSize

                fout = open(outputFile, "w")

                resolutionTime = -1
                isOptimal = false

                # If the method is CPLEX
                if methodFolder == "cplex"

                    # Solve it and get the results
                    isOptimal, x, yh, yv, resolutionTime = cplexSolve(t; regionSize=instanceRegionSize, timeLimit=timeLimit)


                # If the method is one of the heuristics
                else

                    isOptimal, solvedGrid, resolutionTime = heuristicSolve(t; regionSize=instanceRegionSize, timeLimit=timeLimit)

                end

                timedOut = !isOptimal && resolutionTime >= timeLimit

                println(fout, "regionSize = ", instanceRegionSize)
                println(fout, "solveTime = ", timedOut ? "timeout" : string(resolutionTime))
                println(fout, "isOptimal = ", timedOut ? "timeout" : string(isOptimal))
                close(fout)
            end


            # Display the results obtained with the method on the current instance
            solveTime, isOptimal = readResultFile(outputFile)
            println(methodLabel, " optimal: ", isOptimal)
            if solveTime == "timeout"
                println(methodLabel, " time: timeout\n")
            else
                println(methodLabel, " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
            end
        end
    end
end

function connectedComponents(cells::Vector{Tuple{Int, Int}}, nbRows::Int64, nbCols::Int64)
    """
    SPlit the given cells into connected groups

        cells : Cells of a given region
        nbrows : Rows of the original grid
        nbcols : Columns of the original grid
    """

    remaining = Set(cells)
    components = Vector{Vector{Tuple{Int, Int}}}()

    # While there are still cell to be split
    while !isempty(remaining)

        # We pop the first cell of the set
        startCell = first(remaining)
        delete!(remaining, startCell)

        # To store cell connected to the current component. Vector of cells
        component = Tuple{Int, Int}[]

        # Cells to explore next to the current cell
        stack = [startCell]

        while !isempty(stack)
            # Pop cell from stack and put it in the component
            cell = pop!(stack)
            push!(component, cell)

            i, j = cell

            # Vector used to store cell neighbors
            neighbors = Tuple{Int, Int}[]

            if i > 1
                push!(neighbors, (i-1, j))      # Get upper neighbor
            end
            if i < nbRows
                push!(neighbors, (i+1, j))      # Get beneath neighbor
            end
            if j > 1
                push!(neighbors, (i, j-1))      # Get left neighbor
            end
            if j < nbCols
                push!(neighbors, (i, j+1))      # Get right neighbor
            end

            # For each neighbor, if has not been taken yet
                # pop it from set and put it in stack to explore connected components
            for neighbor in neighbors
                if neighbor in remaining
                    delete!(remaining, neighbor)
                    push!(stack, neighbor)
                end
            end

            # As we are analysing elements of the region
             # If those elements are not adjacent, components will be made
        end

        push!(components, component)
    end

    return components
end

"""
Test if a callback was called because an integer solution was found.
"""
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    """
    Is the call back on a integer candidate solution ?

        cb_data : CPLEX callback context.
        context_id : CPLEX callback context identifier.
    """

    if context_id != CPX_CALLBACKCONTEXT_CANDIDATE   # Candidate Integer solution ?
        return false
    end

    ispoint_p = Ref{Cint}()             # Allocate space for a C-int style integer, 
                                            # required for the callback function
    
    # is this an actual candidate solution point?
    ret = CPXcallbackcandidateispoint(cb_data, ispoint_p)

    # request_succeed AND The point is an integer candidate
    return ret == 0 && ispoint_p[] != 0
end
