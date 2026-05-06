# This file contains methods to generate Palisade instances.
include("io.jl")
using Random

"""
Generates a valid random instance of the Palisade game.
- `n`, `m`: Board dimensions.
- `k`: Number of desired regions.
- `fillRatio`: Percentage of clues to leave visible (0.0 to 1.0).
"""
function generateInstance(n::Int, m::Int, k::Int, fillRatio::Float64=0.6)

    if k <= 0
        error("The number of regions must be positive.")
    end
    if (n * m) % k != 0
        error("The board of size $(n)x$(m) cannot be divided into $(k) regions of equal size.")
    end

    regionSize = div(n * m, k)
    regionMap = createRandomRegions(n, m, k, regionSize)

    cluesGrid = zeros(Int, n, m)
    for i in 1:n
        for j in 1:m
            walls = 0

            if i == 1 || regionMap[i, j] != regionMap[i-1, j] walls += 1 end
            if i == n || regionMap[i, j] != regionMap[i+1, j] walls += 1 end
            if j == 1 || regionMap[i, j] != regionMap[i, j-1] walls += 1 end
            if j == m || regionMap[i, j] != regionMap[i, j+1] walls += 1 end

            cluesGrid[i, j] = walls
        end
    end

    puzzleGrid = fill(-1, n, m)
    for i in 1:n
        for j in 1:m
            if rand() <= fillRatio
                puzzleGrid[i, j] = cluesGrid[i, j]
            end
        end
    end

    return puzzleGrid

end

function createRandomRegions(n::Int, m::Int, k::Int, regionSize::Int)
    grid = zeros(Int, n, m)

    if !backtrackRegions!(grid, n, m, k, regionSize, 1)
        error("Failed to generate valid connected regions.")
    end
    return grid

end

function backtrackRegions!(grid::Matrix{Int}, n::Int, m::Int, k::Int, regionSize::Int, currentRegion::Int)
    if currentRegion > k
        return true
    end

    startRow, startCol = 0, 0
    for i in 1:n, j in 1:m
        if grid[i, j] == 0
            startRow, startCol = i, j
            break
        end
    end

    if startRow == 0 return false end

    return growRegion!(grid, n, m, k, regionSize, currentRegion, [(startRow, startCol)], 0)

end

function growRegion!(grid::Matrix{Int}, n::Int, m::Int, k::Int, regionSize::Int, currentRegion::Int, currentCells::Vector{Tuple{Int, Int}}, currentSize::Int)

    if currentSize == regionSize
        if backtrackRegions!(grid, n, m, k, regionSize, currentRegion + 1)
            return true
        else
            return false
        end
    end

    neighbors = Set{Tuple{Int,Int}}()

    if currentSize == 0
        push!(neighbors, currentCells[1])
    else
        for (row, col) in currentCells
            for (rowDelta, colDelta) in [(-1,0), (1,0), (0,-1), (0,1)]
                nextRow, nextCol = row + rowDelta, col + colDelta
                if 1 <= nextRow <= n && 1 <= nextCol <= m && grid[nextRow, nextCol] == 0
                    push!(neighbors, (nextRow, nextCol))
                end
            end
        end
    end

    neighborList = collect(neighbors)
    shuffle!(neighborList)

    for (nextRow, nextCol) in neighborList
        grid[nextRow, nextCol] = currentRegion
        push!(currentCells, (nextRow, nextCol))

        if growRegion!(grid, n, m, k, regionSize, currentRegion, currentCells, currentSize + 1)
            return true
        end

        grid[nextRow, nextCol] = 0
        pop!(currentCells)
    end

    return false

end

"""
Generate all the instances

Remark: a grid is generated only if the corresponding output file does not already exist.
"""
function generateDataSet(numInstances::Int, n::Int, m::Int, k::Int, fillRatio::Float64=0.6)

    outputDir = joinpath(@__DIR__, "..", "data")
    mkpath(outputDir)

    createdCount = 0
    for idx in 1:numInstances
        filename = joinpath(outputDir, "gen_$(n)x$(m)_reg$(k)_$(idx).txt")
        if isfile(filename)
            continue
        end

        grid = generateInstance(n, m, k, fillRatio)

        open(filename, "w") do f
            for i in 1:n
                lineValues = String[]
                for j in 1:m
                    val = grid[i,j] == -1 ? " " : string(grid[i,j])
                    push!(lineValues, val)
                end
                println(f, join(lineValues, ","))
            end
        end

        createdCount += 1
    end

    println("Generated $createdCount new instances in 'data/'.")

end


