# This file contains methods to generate a data set of instances (i.e., sudoku grids)
include("io.jl")

using Random
using Random

function generateInstance(nbRows::Int64, nbCols::Int64, density::Float64)

    grid = fill(-1, nbRows, nbCols)

    for i in 1:nbRows
        for j in 1:nbCols
            if rand() <= density
                grid[i, j] = rand(0:3)
            end
        end
    end

    return grid
end


function generateDataSet()

    if !isdir("data")
        mkdir("data")
    end

    instances = [
        (4, 4, 0.30),
        (5, 5, 0.30),
        (6, 6, 0.35)
    ]

    for (nbRows, nbCols, density) in instances

        grid = generateInstance(nbRows, nbCols, density)

        fileName = "data/generated_$(nbRows)x$(nbCols).txt"

        saveInstance(grid, fileName)
    end
end

