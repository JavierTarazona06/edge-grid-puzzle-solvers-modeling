# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX
using JuMP
import MathOptInterface as MOI

include("generation.jl")

TOL = 0.00001

"""
Solve an instance with CPLEX
"""
function cplexSolve(t::Matrix{Int64}; printValues::Bool=false)


    nbRows = size(t, 1)
    nbCols = size(t, 2)
    regionSize = 5
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
                    W = components[1]
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
                    return
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
function checkConnectedRegions(t::Matrix{Int64}, x)

    vals = JuMP.value.(x)
    nbRows, nbCols = size(t)
    nbRegions = div(nbRows * nbCols, 5)

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
function heuristicSolve()

    # TODO
    println("In file resolution.jl, in method heuristicSolve(), TODO: fix input and output, define the model")
    
end 

"""
Solve all the instances contained in "../data" through CPLEX and heuristics

The results are written in "../res/cplex" and "../res/heuristic"

Remark: If an instance has previously been solved (either by cplex or the heuristic) it will not be solved again
"""
function solveDataSet()

    dataFolder = "../data/"
    resFolder = "../res/"

    # Array which contains the name of the resolution methods
    resolutionMethod = ["cplex"]
    #resolutionMethod = ["cplex", "heuristique"]

    # Array which contains the result folder of each resolution method
    resolutionFolder = resFolder .* resolutionMethod

    # Create each result folder if it does not exist
    for folder in resolutionFolder
        if !isdir(folder)
            mkdir(folder)
        end
    end
            
    global isOptimal = false
    global solveTime = -1

    # For each instance
    # (for each file in folder dataFolder which ends by ".txt")
    for file in filter(x->occursin(".txt", x), readdir(dataFolder))  
        
        println("-- Resolution of ", file)
        t = readInputFile(dataFolder * file)
        
        # For each resolution method
        for methodId in 1:size(resolutionMethod, 1)
            
            outputFile = resolutionFolder[methodId] * "/" * file

            # If the instance has not already been solved by this method
            if !isfile(outputFile)
                
                fout = open(outputFile, "w")  

                resolutionTime = -1
                isOptimal = false
                
                # If the method is cplex
                if resolutionMethod[methodId] == "cplex"
                    
                    # Solve it and get the results
                    isOptimal, x, yh, yv, resolutionTime = cplexSolve(t)

                # If the method is one of the heuristics
                else
                    
                    isSolved = false

                    # Start a chronometer 
                    startingTime = time()
                    
                    # While the grid is not solved and less than 100 seconds are elapsed
                    while !isOptimal && resolutionTime < 100
                        
                        # TODO 
                        println("In file resolution.jl, in method solveDataSet(), TODO: fix heuristicSolve() arguments and returned values")
                        
                        # Solve it and get the results
                        isOptimal, resolutionTime = heuristicSolve()

                        # Stop the chronometer
                        resolutionTime = time() - startingTime
                        
                    end

                    # Write the solution (if any)
                    if isOptimal

                        # TODO
                        println("In file resolution.jl, in method solveDataSet(), TODO: write the heuristic solution in fout")
                        
                    end 
                end

                println(fout, "solveTime = ", resolutionTime) 
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end


            # Display the results obtained with the method on the current instance
            include(outputFile)
            println(resolutionMethod[methodId], " optimal: ", isOptimal)
            println(resolutionMethod[methodId], " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
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
