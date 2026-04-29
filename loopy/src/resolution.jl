# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX

include("generation.jl")

TOL = 0.00001

"""
Solve an instance with CPLEX
"""
using JuMP
using CPLEX

function cplexSolve(t::Matrix{Int64})

    nbRows = size(t, 1)
    nbCols = size(t, 2)

    # Create the model
    m = Model(CPLEX.Optimizer)

    # -----------------------------
    # Variables
    # -----------------------------
    # h[i,j] = 1 si l'arête horizontale de la ligne i et colonne j est prise
    # Il y a nbRows+1 lignes d'arêtes horizontales et nbCols colonnes
    @variable(m, h[1:nbRows+1, 1:nbCols], Bin)

    # v[i,j] = 1 si l'arête verticale de la ligne i et colonne j est prise
    # Il y a nbRows lignes d'arêtes verticales et nbCols+1 colonnes
    @variable(m, v[1:nbRows, 1:nbCols+1], Bin)

    # y[i,j] = 1 si le sommet (i,j) appartient à la boucle, 0 sinon
    @variable(m, y[1:nbRows+1, 1:nbCols+1], Bin)

    # -----------------------------
    # Objective
    # -----------------------------
    # On cherche seulement une solution réalisable
    @objective(m, Min, 0)

    # -----------------------------
    # Constraints on numbered cells
    # -----------------------------
    # Pour chaque case contenant un indice, la somme des 4 arêtes autour
    # de la case doit être égale à cet indice
    for i in 1:nbRows
        for j in 1:nbCols
            if t[i, j] != -1
                @constraint(m,
                    h[i, j] + h[i+1, j] + v[i, j] + v[i, j+1] == t[i, j]
                )
            end
        end
    end

    # -----------------------------
    # Constraints on vertices
    # -----------------------------
    # Chaque sommet doit avoir degré 0 ou 2
    # Somme des arêtes incidentes = 2*y[i,j]
    for i in 1:nbRows+1
        for j in 1:nbCols+1

            expr = 0

            # arête horizontale à gauche du sommet
            if j > 1
                expr += h[i, j-1]
            end

            # arête horizontale à droite du sommet
            if j <= nbCols
                expr += h[i, j]
            end

            # arête verticale au-dessus du sommet
            if i > 1
                expr += v[i-1, j]
            end

            # arête verticale en-dessous du sommet
            if i <= nbRows
                expr += v[i, j]
            end

            @constraint(m, expr == 2 * y[i, j])
        end
    end

    # -----------------------------
    # Solve
    # -----------------------------
    start = time()
    optimize!(m)
    solveTime = time() - start

    # -----------------------------
    # Return
    # -----------------------------
    isFeasible = JuMP.primal_status(m) == MOI.FEASIBLE_POINT

    return isFeasible, h, v, solveTime
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
        readInputFile(dataFolder * file)

        # TODO
        println("In file resolution.jl, in method solveDataSet(), TODO: read value returned by readInputFile()")
        
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
                    
                    # TODO 
                    println("In file resolution.jl, in method solveDataSet(), TODO: fix cplexSolve() arguments and returned values")
                    
                    # Solve it and get the results
                    isOptimal, resolutionTime = cplexSolve()
                    
                    # If a solution is found, write it
                    if isOptimal
                        # TODO
                        println("In file resolution.jl, in method solveDataSet(), TODO: write cplex solution in fout") 
                    end

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
                
                # TODO
                println("In file resolution.jl, in method solveDataSet(), TODO: write the solution in fout") 
                close(fout)
            end


            # Display the results obtained with the method on the current instance
            include(outputFile)
            println(resolutionMethod[methodId], " optimal: ", isOptimal)
            println(resolutionMethod[methodId], " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
        end         
    end 
end
