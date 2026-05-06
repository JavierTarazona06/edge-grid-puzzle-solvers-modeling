# This file contains methods to solve an instance (heuristically or with CPLEX)
using CPLEX
using JuMP
using Random

include("generation.jl")

TOL = 0.00001

"""
Solve an instance with CPLEX
"""


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

    return isFeasible, solveTime, h, v
end

"""
Solve an instance with CPLEX + Callback to add lazy constraints to eliminate subtours
"""

"""
Check if the current point is an integer point (i.e. all variables are integer)
"""
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)

    if context_id != CPX_CALLBACKCONTEXT_CANDIDATE
        return false
    end

    ispoint_p = Ref{Cint}()
    ret = CPXcallbackcandidateispoint(cb_data, ispoint_p)

    return ret == 0 && ispoint_p[] != 0
end

function cplexSolveWithCallback(t::Matrix{Int64})

    nbRows = size(t, 1)
    nbCols = size(t, 2)

    m = Model(CPLEX.Optimizer)

    @variable(m, h[1:nbRows+1, 1:nbCols], Bin)
    @variable(m, v[1:nbRows, 1:nbCols+1], Bin)
    @variable(m, y[1:nbRows+1, 1:nbCols+1], Bin)

    @objective(m, Min, 0)

    for i in 1:nbRows
        for j in 1:nbCols
            if t[i, j] != -1
                @constraint(m, h[i,j] + h[i+1,j] + v[i,j] + v[i,j+1] == t[i,j])
            end
        end
    end

    for i in 1:nbRows+1
        for j in 1:nbCols+1
            expr = 0
            if j > 1
                expr += h[i,j-1]
            end
            if j <= nbCols
                expr += h[i,j]
            end
            if i > 1
                expr += v[i-1,j]
            end
            if i <= nbRows
                expr += v[i,j]
            end
            @constraint(m, expr == 2y[i,j])
        end
    end

    function callback_loopy(cb_data::CPLEX.CallbackContext, context_id::Clong)

        if isIntegerPoint(cb_data, context_id)

            CPLEX.load_callback_variable_primal(cb_data, context_id)

            h_val = callback_value.(cb_data, h)
            v_val = callback_value.(cb_data, v)

            edges = Tuple{Symbol,Int,Int}[]
            endpoints = Dict{Tuple{Symbol,Int,Int}, Tuple{Tuple{Int,Int},Tuple{Int,Int}}}()

            for i in 1:nbRows+1, j in 1:nbCols
                if h_val[i,j] > 0.5
                    e = (:h, i, j)
                    push!(edges, e)
                    endpoints[e] = ((i,j), (i,j+1))
                end
            end

            for i in 1:nbRows, j in 1:nbCols+1
                if v_val[i,j] > 0.5
                    e = (:v, i, j)
                    push!(edges, e)
                    endpoints[e] = ((i,j), (i+1,j))
                end
            end

            vertexEdges = Dict{Tuple{Int,Int}, Vector{Tuple{Symbol,Int,Int}}}()

            for e in edges
                p1, p2 = endpoints[e]
                push!(get!(vertexEdges, p1, Tuple{Symbol,Int,Int}[]), e)
                push!(get!(vertexEdges, p2, Tuple{Symbol,Int,Int}[]), e)
            end

            visited = Set{Tuple{Symbol,Int,Int}}()
            components = Vector{Vector{Tuple{Symbol,Int,Int}}}()

            for e0 in edges
                if e0 in visited
                    continue
                end

                component = Tuple{Symbol,Int,Int}[]
                stack = [e0]

                while !isempty(stack)
                    e = pop!(stack)

                    if e in visited
                        continue
                    end

                    push!(visited, e)
                    push!(component, e)

                    p1, p2 = endpoints[e]

                    for p in (p1, p2)
                        for e2 in vertexEdges[p]
                            if !(e2 in visited)
                                push!(stack, e2)
                            end
                        end
                    end
                end

                push!(components, component)
            end

            if length(components) > 1
                for component in components

                    vars = []

                    for e in component
                        if e[1] == :h
                            push!(vars, h[e[2], e[3]])
                        else
                            push!(vars, v[e[2], e[3]])
                        end
                    end

                    cstr = @build_constraint(sum(vars) <= length(component) - 1)
                    MOI.submit(m, MOI.LazyConstraint(cb_data), cstr)
                end
            end
        end
    end

    MOI.set(m, MOI.NumberOfThreads(), 1)
    MOI.set(m, CPLEX.CallbackFunction(), callback_loopy)

    start = time()
    optimize!(m)
    solveTime = time() - start

    isFeasible = JuMP.primal_status(m) == MOI.FEASIBLE_POINT

    return isFeasible, solveTime, h, v
end


"""
Heuristically solve an instance
"""


function scoreLoopy(t, h, v)
    nbRows, nbCols = size(t)
    score = 0

    for i in 1:nbRows, j in 1:nbCols
        if t[i,j] != -1
            s = h[i,j] + h[i+1,j] + v[i,j] + v[i,j+1]
            score += abs(s - t[i,j])
        end
    end

    for i in 1:nbRows+1, j in 1:nbCols+1
        deg = 0
        if j > 1
            deg += h[i,j-1]
        end
        if j <= nbCols
            deg += h[i,j]
        end
        if i > 1
            deg += v[i-1,j]
        end
        if i <= nbRows
            deg += v[i,j]
        end

        if deg != 0 && deg != 2
            score += 5
        end
    end

    return score
end


function heuristicSolve(t::Matrix{Int64}; timeLimit::Float64=20.0)

    nbRows, nbCols = size(t)

    h = rand(0:1, nbRows+1, nbCols)
    v = rand(0:1, nbRows, nbCols+1)

    bestH = copy(h)
    bestV = copy(v)
    bestScore = scoreLoopy(t, h, v)

    start = time()

    while time() - start < timeLimit && bestScore > 0

        h2 = copy(bestH)
        v2 = copy(bestV)

        if rand() < 0.5
            i = rand(1:nbRows+1)
            j = rand(1:nbCols)
            h2[i,j] = 1 - h2[i,j]
        else
            i = rand(1:nbRows)
            j = rand(1:nbCols+1)
            v2[i,j] = 1 - v2[i,j]
        end

        newScore = scoreLoopy(t, h2, v2)

        if newScore <= bestScore || rand() < 0.01
            bestH = h2
            bestV = v2
            bestScore = newScore
        end
    end

    isOptimal = bestScore == 0
    solveTime = time() - start

    return isOptimal, solveTime, bestH, bestV
end

function writeLoopySolution(fout, h, v)

    println(fout, "h = [")
    for i in 1:size(h,1)
        println(fout, join(h[i,:], " "))
    end
    println(fout, "]")

    println(fout, "v = [")
    for i in 1:size(v,1)
        println(fout, join(v[i,:], " "))
    end
    println(fout, "]")
end

"""
Solve all the instances contained in "../data" through CPLEX and heuristics

The results are written in "../res/cplex" and "../res/heuristic"

Remark: If an instance has previously been solved (either by cplex or the heuristic) it will not be solved again
"""
function solveDataSet()

    dataFolder = "data/"
    resFolder = "res/"

    resolutionMethod = ["cplex", "heuristique"]

    if !isdir(resFolder)
        mkdir(resFolder)
    end

    for method in resolutionMethod
        folder = resFolder * method
        if !isdir(folder)
            mkdir(folder)
        end
    end

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))

        println("-- Resolution of ", file)

        grid = readInputFile(dataFolder * file)

        for method in resolutionMethod

            outputFile = resFolder * method * "/" * file

            if !isfile(outputFile)

                fout = open(outputFile, "w")

                if method == "cplex"

                    isOptimal, solveTime, h, v = cplexSolveWithCallback(grid)

                    if isOptimal
                        hVal = round.(Int, JuMP.value.(h))
                        vVal = round.(Int, JuMP.value.(v))
                        writeLoopySolution(fout, hVal, vVal)
                    end

                else

                    isOptimal, solveTime, h, v = heuristicSolve(grid)

                    if isOptimal
                        writeLoopySolution(fout, h, v)
                    end
                end

                println(fout, "solveTime = ", solveTime)
                println(fout, "isOptimal = ", isOptimal)

                close(fout)
            end

            include(outputFile)

            println(method, " optimal: ", isOptimal)
            println(method, " time: ", string(round(solveTime, sigdigits=2)), "s\n")
        end
    end
end