# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX                                 # IBM's Mathematical Optimization Solver
using JuMP                                  # Julia's package for Mathematical Optimization
import MathOptInterface as MOI              # Low Level interface of JUMP, used for CPLEX callbacks

include("generation.jl")

TOL = 0.00001                               # Tolerance for numerical issues in the callback

"""
Solve an instance with CPLEX
"""
function cplexSolve(t::Matrix{Int64}; regionSize::Int64=5, printValues::Bool=false)
    """
    Solve an instance with CPLEX

        t : Game cells
        regionSize : Number of cells in each region
        printValues : If true, the returned values are printed
    """

    nbRows = size(t, 1)                                      # Get number of rows. Indexed with 1
    nbCols = size(t, 2)                                      # Get number of columns. Indexed with 2

    # Check region size is positive and divides the area of the grid
    if regionSize <= 0
        error("regionSize must be strictly positive.")
    end
    if (nbRows * nbCols) % regionSize != 0
        error("regionSize must divide area nbRows * nbCols.")
    end

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

                    # Get the first component as a set
                    W = components[1]
                    Wset = Set(W)

                    # List to store zh and zv variables to check connectivity
                    borderTerms = Any[]

                    for (i, j) in W
                        # Only if neighbors are not in the Wset

                        if i > 1 && !((i-1, j) in Wset)
                            push!(borderTerms, zh[i-1, j, p]) # Get value if upper cell is also at region p
                        end

                        if i < nbRows && !((i+1, j) in Wset)
                            push!(borderTerms, zh[i, j, p]) # Get value if cell beneath is also at region p
                        end

                        if j > 1 && !((i, j-1) in Wset)
                            push!(borderTerms, zv[i, j-1, p]) # Get value if left cell is also at region p
                        end

                        if j < nbCols && !((i, j+1) in Wset)
                            push!(borderTerms, zv[i, j, p]) # Get value if right cell is also at region p
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
function checkConnectedRegions(t::Matrix{Int64}, x; regionSize::Int64=5)

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
