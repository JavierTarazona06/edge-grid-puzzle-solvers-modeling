# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX
using JuMP

include("generation.jl")

TOL = 0.00001

"""
Solve an instance with CPLEX
"""
function cplexSolve(t::Matrix{Int64})


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
