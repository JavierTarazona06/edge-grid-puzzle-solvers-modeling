include("io.jl")

using Random

function generateInstance(nbRows::Int64, nbCols::Int64, density::Float64)

    grid = fill(-1, nbRows, nbCols)

    for i in 1:nbRows
        for j in 1:nbCols
            if rand() <= density
                grid[i, j] = rand(0:4)
            end
        end
    end

    return grid
end


function generateDataSet()

    dataDir = joinpath(@__DIR__, "..", "data")

    if !isdir(dataDir)
        mkdir(dataDir)
    end

    sizes = [
        (4, 4),
        (5, 5),
        (6, 6),
        (7, 7),
        (8, 8)
    ]

    densities = [0.20, 0.30, 0.40]

    nbInstances = 5

    for (nbRows, nbCols) in sizes
        for density in densities
            for id in 1:nbInstances

                fileName = joinpath(
                    dataDir,
                    "generated_$(nbRows)x$(nbCols)_d$(density)_$(id).txt"
                )

                if !isfile(fileName)
                    grid = generateInstance(nbRows, nbCols, density)
                    saveInstance(grid, fileName)
                    println("Instance generated: ", fileName)
                else
                    println("Instance already exists: ", fileName)
                end

            end
        end
    end
end