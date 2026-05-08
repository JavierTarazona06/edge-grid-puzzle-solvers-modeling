# This file contains functions related to reading, writing and displaying a grid and experimental results

using JuMP
using Plots
import GR
using Printf

"""
Read an instance from an input file

- Argument:
inputFile: path of the input file
"""
function readInputFile(inputFile::String)

    # Open file
    datafile = open(inputFile)
    lines = readlines(datafile)
    close(datafile)

    # Dimensions
    n = length(lines)
    m = length(split(lines[1], ","))

    # Grid (use -1 for empty cells)
    grid = Array{Int64}(undef, n, m) # Values not yet defined

    # Parse file
    for i in 1:n
        lineSplit = split(lines[i], ",")

        for j in 1:m
            val = strip(lineSplit[j]) # Remove spaces

            if val == ""
                grid[i, j] = -1
            else
                grid[i, j] = parse(Int64, val)
            end
        end
    end

    # Display the read matrix line by line
    println("Grid read from file ", inputFile, " :")
    for i in 1:n
        println(grid[i, :])
    end

    return grid
end

"""
Display a grid represented by a 2-dimensional array

Argument:
- grid: matrix with -1 for empty clues
"""
function displayGrid(grid::Matrix{Int64})

    n, m = size(grid)

    println("\n=== Initial grid ===\n")

    println("-" ^ (m*4+1))

    for l in 1:n
        print("|")
        for c in 1:m

            val = grid[l, c] == -1 ? " " : string(grid[l, c])
            print(" ", val, " |")
        end

        println()

        println("-" ^ (m*4+1))
    end
    println()

end

"""
Display a CPLEX solution.

Arguments:
- grid: puzzle clues
- yh: horizontal wall variables or values
- yv: vertical wall variables or values
"""
function displaySolution(grid::Matrix{Int64}, yh, yv)

    n, m = size(grid)

    yh_vals = yh isa AbstractArray{<:JuMP.VariableRef} ? JuMP.value.(yh) : yh
    yv_vals = yv isa AbstractArray{<:JuMP.VariableRef} ? JuMP.value.(yv) : yv

    println("\n=== Solved grid ===\n")

    println("+" * "---+" ^ m)

    for row in 1:n
        print("|")

        for col in 1:m

            val = grid[row, col] == -1 ? " " : string(grid[row, col])
            print(" ", val, " ")

            if col < m
                verticalWall = round(Int, yv_vals[row, col]) == 1 ? "|" : " "
                print(verticalWall)
            end
        end

        println("|")

        if row < n
            print("+")
            for col in 1:m
                horizontalWall = round(Int, yh_vals[row, col]) == 1 ? "---" : "   "
                print(horizontalWall, "+")
            end
            println()
        end

    end

    println("+" * "---+" ^ m)
    println()
end


"""
Create a PDF performance diagram from the result files in the res subfolders.
Each subfolder produces one curve.
"""
function performanceDiagram(outputFile::String; generatedOnly::Bool=false)

    resultFolder = joinpath(@__DIR__, "..", "res")
    mkpath(dirname(outputFile))

    folderNames = String[]
    results = Vector{Vector{Float64}}()
    maxSolveTime = 0.0

    for file in sort(filter(file -> isdir(joinpath(resultFolder, file)), readdir(resultFolder)))
        path = joinpath(resultFolder, file)

        solveTimes = Float64[]

        for resultFile in sort(filter(x -> endswith(x, ".txt") && (!generatedOnly || startswith(x, "gen_")), readdir(path)))
            solveTime, isOptimal = readResultFile(joinpath(path, resultFile))

            if isOptimal === true
                push!(solveTimes, solveTime)
                maxSolveTime = max(maxSolveTime, solveTime)
            end
        end

        push!(folderNames, file)
        push!(results, sort(solveTimes))
    end

    if isempty(folderNames)
        error("No result folders found in $resultFolder")
    end

    maxX = max(maxSolveTime, 1.0e-6)
    p = plot(
        legend = :bottomright,
        xaxis = "Time (s)",
        yaxis = "Solved instances",
        xlims = (0, maxX),
        ylims = (0, maximum(length.(results))),
    )

    for (method, solveTimes) in zip(folderNames, results)
        x = Float64[0.0]
        y = Int[0]

        for (id, solveTime) in enumerate(solveTimes)
            push!(x, solveTime)
            push!(y, id - 1)
            push!(x, solveTime)
            push!(y, id)
        end

        push!(x, maxX)
        push!(y, length(solveTimes))
        plot!(p, x, y, label = method, linewidth = 3)
    end

    savefig(p, outputFile)
    println("Performance diagram written to ", outputFile)
end

"""
Create a latex file which contains an array with the results of the ../res folder.
Each subfolder of the ../res folder contains the results of a resolution method.

Arguments
- outputFile: path of the output file

Prerequisites:
- Each subfolder must contain text files
- Each text file correspond to the resolution of one instance
- Each text file contains a variable "solveTime" and a variable "isOptimal"
"""
function readResultFile(resultFile::String)
    solveTime = nothing
    isOptimal = nothing

    for line in eachline(resultFile)
        strippedLine = strip(line)

        if startswith(strippedLine, "solveTime")
            value = strip(split(strippedLine, "=", limit=2)[2])
            solveTime = value in ("timeout", "\"timeout\"") ? "timeout" : parse(Float64, value)
        elseif startswith(strippedLine, "isOptimal")
            value = strip(split(strippedLine, "=", limit=2)[2])
            isOptimal = value in ("timeout", "\"timeout\"") ? "timeout" : parse(Bool, value)
        end
    end

    if solveTime === nothing || isOptimal === nothing
        error("Missing solveTime or isOptimal in result file: $resultFile")
    end

    return solveTime, isOptimal
end

function resultsArray(outputFile::String; generatedOnly::Bool=false)

    resultFolder = joinpath(@__DIR__, "..", "res")
    mkpath(dirname(outputFile))

    # Open the latex output file
    fout = open(outputFile, "w")

    # Print the latex file output
    println(fout, raw"""\documentclass{article}

\usepackage[english]{babel}
\usepackage[utf8]{inputenc}
\usepackage{multicol}

\setlength{\hoffset}{-18pt}
\setlength{\oddsidemargin}{0pt}
\setlength{\evensidemargin}{9pt}
\setlength{\marginparwidth}{54pt}
\setlength{\textwidth}{481pt}
\setlength{\voffset}{-18pt}
\setlength{\marginparsep}{7pt}
\setlength{\topmargin}{0pt}
\setlength{\headheight}{13pt}
\setlength{\headsep}{10pt}
\setlength{\footskip}{27pt}
\setlength{\textheight}{668pt}

\begin{document}""")

    header = raw"""
\begin{center}
\renewcommand{\arraystretch}{1.4}
 \begin{tabular}{l"""

    # Result subfolders correspond to the available resolution methods.
    folderNames = sort(filter(folder -> isdir(joinpath(resultFolder, folder)), readdir(resultFolder)))

    # List of all the instances solved by at least one resolution method
    solvedInstances = String[]

    for folder in folderNames
        path = joinpath(resultFolder, folder)
        append!(solvedInstances, filter(x -> endswith(x, ".txt") && (!generatedOnly || startswith(x, "gen_")), readdir(path)))
    end

    # Only keep one string for each instance solved
    solvedInstances = sort(unique(solvedInstances))

    # For each resolution method, add two columns in the array
    for folder in folderNames
        header *= "rr"
    end

    header *= "}\n\t\\hline\n"

    # Create the header line which contains the methods name
    for folder in folderNames
        header *= " & \\multicolumn{2}{c}{\\textbf{" * folder * "}}"
    end

    header *= "\\\\\n\\textbf{Instance} "

    # Create the second header line with the content of the result columns
    for folder in folderNames
        header *= " & \\textbf{Time (s)} & \\textbf{Optimal?} "
    end

    header *= "\\\\\\hline\n"

    footer = raw"""\hline\end{tabular}
\end{center}

"""
    println(fout, header)

    # On each page an array will contain at most maxInstancePerPage lines with results
    maxInstancePerPage = 30
    rowId = 1

    # For each solved files
    for solvedInstance in solvedInstances

        # If we do not start a new array on a new page
        if rem(rowId, maxInstancePerPage) == 0
            println(fout, footer, "\\newpage")
            println(fout, header)
        end

        # Replace the potential underscores '_' in file names
        print(fout, replace(solvedInstance, "_" => "\\_"))

        # For each resolution method
        for method in folderNames

            path = joinpath(resultFolder, method, solvedInstance)

            # If the instance has been solved by this method
            if isfile(path)

                solveTime, isOptimal = readResultFile(path)

                if solveTime == "timeout" || isOptimal == "timeout"
                    print(fout, " & timeout & timeout")
                else
                    optimalText = isOptimal ? "\$\\times\$" : "-"
                    print(fout, " & ", @sprintf("%.6f", solveTime), " & ", optimalText)
                end

            # If the instance has not been solved by this method
            else
                print(fout, " & - & - ")
            end
        end

        println(fout, "\\\\")

        rowId += 1
    end

    # Print the end of the latex file
    println(fout, footer)

    println(fout, "\\end{document}")

    close(fout)

end
