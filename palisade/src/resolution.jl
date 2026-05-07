# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX
using JuMP
import MathOptInterface as MOI

include("generation.jl")

TOL = 0.00001

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
                    nbRegions::Union{Nothing,Int}=nothing)


    nbRows = size(t, 1)
    nbCols = size(t, 2)
    regionSize = resolveRegionSize(t; regionSize=regionSize, nbRegions=nbRegions)

    nbRegions = div(nbRows * nbCols, regionSize)

    # Create the model
    m = Model(CPLEX.Optimizer)

    # -----------------------------
    # Variables
    # -----------------------------

    # Cell-to-region assignment - x[row, col, region]
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

        # Linearization on vertically adjacent cells
    for i in 1:nbRows-1
        for j in 1:nbCols
            for p in 1:nbRegions
                @constraint(m, zh[i, j, p] <= x[i, j, p])
                @constraint(m, zh[i, j, p] <= x[i+1, j, p])
                @constraint(m, zh[i, j, p] >= x[i, j, p] + x[i+1, j, p] - 1)
            end
        end
    end

        # Linearization on horizontally adjacent cells
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
    for i in 1:nbRows-1
        for j in 1:nbCols
            @constraint(m, yh[i, j] + sum(zh[i, j, p] for p in 1:nbRegions) == 1)
        end
    end

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
                    borderCount += 1
                end
                if i == nbRows
                    borderCount += 1
                end
                if j == 1
                    borderCount += 1
                end
                if j == nbCols
                    borderCount += 1
                end

                expr = borderCount

                # Add the palisades adjacent to the cell (i, j). Not borders of the grid.
                if i > 1
                    expr += yh[i-1, j]
                end
                if i < nbRows
                    expr += yh[i, j]
                end
                if j > 1
                    expr += yv[i, j-1]
                end
                if j < nbCols
                    expr += yv[i, j]
                end

                @constraint(m, expr == t[i, j])
            end
        end
    end

    function callback_connectivity(cb_data::CPLEX.CallbackContext, context_id::Clong)

        if isIntegerPoint(cb_data, context_id)

            CPLEX.load_callback_variable_primal(cb_data, context_id)
            x_val = callback_value.(cb_data, x)

            for p in 1:nbRegions
                cells = [(i, j) for i in 1:nbRows, j in 1:nbCols if x_val[i, j, p] > 0.9]
                components = connectedComponents(cells, nbRows, nbCols)

                if length(components) > 1
                    for W in components
                        Wset = Set(W)

                        borderTerms = Any[]

                        for (i, j) in W

                            if i > 1 && !((i-1, j) in Wset)
                                push!(borderTerms, zh[i-1, j, p])
                            end

                            if i < nbRows && !((i+1, j) in Wset)
                                push!(borderTerms, zh[i, j, p])
                            end

                            if j > 1 && !((i, j-1) in Wset)
                                push!(borderTerms, zv[i, j-1, p])
                            end

                            if j < nbCols && !((i, j+1) in Wset)
                                push!(borderTerms, zv[i, j, p])
                            end
                        end

                        leftSide = sum(x[i, j, p] for (i, j) in W)
                        rightSide = length(W) - 1

                        if length(borderTerms) > 0
                            rightSide += sum(borderTerms)
                        end

                        cstr = @build_constraint(leftSide <= rightSide)
                        MOI.submit(m, MOI.LazyConstraint(cb_data), cstr)
                    end
                end
            end
        end
    end

    # CPLEX callbacks are used with one thread.
    MOI.set(m, MOI.NumberOfThreads(), 1)
    MOI.set(m, CPLEX.CallbackFunction(), callback_connectivity)

    # Start a chronometer
    start = time()

    # Solve the model
    optimize!(m)

    # Return:
    # 1 - true if an optimum is found
    # 2 - the resolution time
    return JuMP.is_solved_and_feasible(m), x, yh, yv, time() - start

end

"""
Check whether assigning a cell to a region can still satisfy the local clue constraints.
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
function backtrackSolve!(grid::Matrix{Int}, clues::Matrix{Int}, n::Int, m::Int, k::Int, regionSize::Int, row::Int, col::Int)
    if col > m
        row += 1
        col = 1
    end

    if row > n
        return checkConnectivity(grid, n, m, k, regionSize)
    end

    if grid[row, col] != 0
        return backtrackSolve!(grid, clues, n, m, k, regionSize, row, col + 1)
    end

    for regionId in 1:k
        if isValidMove(grid, clues, row, col, regionId, regionSize)

            grid[row, col] = regionId

            if backtrackSolve!(grid, clues, n, m, k, regionSize, row, col + 1)
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
                        nbRegions::Union{Nothing,Int}=nothing)
    startTime = time()
    n, m = size(clues)
    regionSize = resolveRegionSize(clues; regionSize=regionSize, nbRegions=nbRegions)

    k = div(n * m, regionSize)
    grid = zeros(Int, n, m)

    isSolved = backtrackSolve!(grid, clues, n, m, k, regionSize, 1, 1)

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
                        defaultRegionSize::Union{Nothing,Int}=5)

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
                    isOptimal, x, yh, yv, resolutionTime = cplexSolve(t; regionSize=instanceRegionSize)


                # If the method is one of the heuristics
                else

                    isOptimal, solvedGrid, resolutionTime = heuristicSolve(t; regionSize=instanceRegionSize)

                end

                println(fout, "regionSize = ", instanceRegionSize)
                println(fout, "solveTime = ", resolutionTime)
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end


            # Display the results obtained with the method on the current instance
            include(outputFile)
            println(methodLabel, " optimal: ", isOptimal)
            println(methodLabel, " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
        end
    end
end

function connectedComponents(cells::Vector{Tuple{Int, Int}}, nbRows::Int64, nbCols::Int64)

    remaining = Set(cells)
    components = Vector{Vector{Tuple{Int, Int}}}()

    while !isempty(remaining)
        startCell = first(remaining)
        delete!(remaining, startCell)

        component = Tuple{Int, Int}[]
        stack = [startCell]

        while !isempty(stack)
            cell = pop!(stack)
            push!(component, cell)

            i, j = cell
            neighbors = Tuple{Int, Int}[]

            if i > 1
                push!(neighbors, (i-1, j))
            end
            if i < nbRows
                push!(neighbors, (i+1, j))
            end
            if j > 1
                push!(neighbors, (i, j-1))
            end
            if j < nbCols
                push!(neighbors, (i, j+1))
            end

            for neighbor in neighbors
                if neighbor in remaining
                    delete!(remaining, neighbor)
                    push!(stack, neighbor)
                end
            end
        end

        push!(components, component)
    end

    return components
end

"""
Test if a callback was called because an integer solution was found.
"""
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)

    if context_id != CPX_CALLBACKCONTEXT_CANDIDATE
        return false
    end

    ispoint_p = Ref{Cint}()
    ret = CPXcallbackcandidateispoint(cb_data, ispoint_p)

    return ret == 0 && ispoint_p[] != 0
end
