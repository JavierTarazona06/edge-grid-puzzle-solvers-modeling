include("io.jl")

using Statistics

const TIMEOUT_SEC = 100.0
const METHODS = [("cplex", "CPLEX"), ("heuristic", "Heuristique")]

const PALISADE_DIR = normpath(joinpath(@__DIR__, ".."))
const DATA_DIR = joinpath(PALISADE_DIR, "data")
const RESULT_DIR = joinpath(PALISADE_DIR, "res")
const REPORT_DIR = normpath(joinpath(PALISADE_DIR, "..", "docs", "rapport"))
const GENERATED_DIR = joinpath(REPORT_DIR, "generated")
const IMAGE_DIR = joinpath(REPORT_DIR, "imgs", "palisade")

escape_latex(text::AbstractString) = replace(text, "_" => "\\_", "%" => "\\%", "&" => "\\&")
latex_code(text::AbstractString) = "\\texttt{" * escape_latex(text) * "}"
format_density(value::Float64) = @sprintf("%.3f", value)
format_float(value::Float64) = @sprintf("%.2f", value)
format_time(value::Float64, status::String) = status == "timeout" ? "timeout" : format_float(value)

function parse_instance_name(file::String)
    m = match(r"^gen_(\d+)x(\d+)_reg(\d+)_(\d+)\.txt$", file)
    m === nothing && error("Unexpected instance filename: $file")

    n = parse(Int, m.captures[1])
    mcols = parse(Int, m.captures[2])
    k = parse(Int, m.captures[3])

    return (
        instance = splitext(file)[1],
        family = "$(n)x$(mcols) reg$(k)",
        n = n,
        m = mcols,
        N = n * mcols,
        k = k,
        s = div(n * mcols, k),
    )
end

function count_clues(path::String)
    nbClues = 0
    nb1 = 0
    nb2 = 0
    nb3 = 0

    for line in eachline(path)
        for rawValue in split(line, ",")
            value = strip(rawValue)
            if isempty(value)
                continue
            end

            clue = parse(Int, value)
            nbClues += 1
            if clue == 1
                nb1 += 1
            elseif clue == 2
                nb2 += 1
            elseif clue == 3
                nb3 += 1
            end
        end
    end

    return (nbClues = nbClues, nb1 = nb1, nb2 = nb2, nb3 = nb3)
end

function normalize_result(path::String)
    solveTime, isOptimal = readResultFile(path)

    if solveTime == "timeout" || isOptimal == "timeout"
        return (solveTimeSec = TIMEOUT_SEC, status = "timeout")
    elseif isOptimal === true
        return (solveTimeSec = solveTime, status = "solved")
    else
        return (solveTimeSec = solveTime, status = "unsolved")
    end
end

function build_rows()
    rows = NamedTuple[]
    instanceFiles = sort(filter(file -> startswith(file, "gen_") && endswith(file, ".txt"), readdir(DATA_DIR)))

    for file in instanceFiles
        instanceInfo = parse_instance_name(file)
        clueInfo = count_clues(joinpath(DATA_DIR, file))

        for (methodFolder, methodLabel) in METHODS
            resultInfo = normalize_result(joinpath(RESULT_DIR, methodFolder, file))
            push!(rows, (
                instance = instanceInfo.instance,
                family = instanceInfo.family,
                method = methodLabel,
                n = instanceInfo.n,
                m = instanceInfo.m,
                N = instanceInfo.N,
                k = instanceInfo.k,
                s = instanceInfo.s,
                nbClues = clueInfo.nbClues,
                clueDensity = clueInfo.nbClues / instanceInfo.N,
                nb1 = clueInfo.nb1,
                nb2 = clueInfo.nb2,
                nb3 = clueInfo.nb3,
                solveTimeSec = resultInfo.solveTimeSec,
                status = resultInfo.status,
            ))
        end
    end

    sort!(rows, by = row -> (row.N, row.k, row.instance, row.method))
    return rows
end

function family_rows(rows, family::String, method::String="")
    if isempty(method)
        return [row for row in rows if row.family == family]
    end
    return [row for row in rows if row.family == family && row.method == method]
end

function families(rows)
    labels = sort(unique([row.family for row in rows]), by = label -> begin
        row = first(filter(r -> r.family == label, rows))
        (row.N, row.k, label)
    end)

    return [
        begin
            row = first(filter(r -> r.family == label, rows))
            (
                family = label,
                n = row.n,
                m = row.m,
                N = row.N,
                k = row.k,
                s = row.s,
                count = length(unique([r.instance for r in rows if r.family == label])),
            )
        end
        for label in labels
    ]
end

function method_totals(rows, method::String)
    methodRows = [row for row in rows if row.method == method]
    return (
        total = length(methodRows),
        solved = count(row -> row.status == "solved", methodRows),
    )
end

function first_timeout_family(rows, method::String)
    for family in families(rows)
        currentRows = family_rows(rows, family.family, method)
        if !isempty(currentRows) && all(row -> row.status == "timeout", currentRows)
            return family
        end
    end
    return nothing
end

function largest_solved_family(rows, method::String)
    solvedRows = [row for row in rows if row.method == method && row.status == "solved"]
    row = solvedRows[argmax([solvedRow.N for solvedRow in solvedRows])]
    return (n = row.n, m = row.m, N = row.N)
end

function contrast_instance(rows, instance::String, method::String)
    return only([row for row in rows if row.instance == instance && row.method == method])
end

function latex_board(n::Int, m::Int)
    return "\$" * string(n) * " \\\\times " * string(m) * "\$"
end

function write_macro(io, name::String, value::String)
    println(io, "\\newcommand{\\", name, "}{", value, "}")
end

function write_macros(rows, outputPath::String)
    cplex = method_totals(rows, "CPLEX")
    heuristic = method_totals(rows, "Heuristique")
    heuristicTimeout = first_timeout_family(rows, "Heuristique")
    cplexTimeout = first_timeout_family(rows, "CPLEX")
    cplexLargest = largest_solved_family(rows, "CPLEX")
    slow = contrast_instance(rows, "gen_8x5_reg8_1", "CPLEX")
    fast = contrast_instance(rows, "gen_8x5_reg8_2", "CPLEX")

    open(outputPath, "w") do io
        write_macro(io, "PalisadeTimeoutLimit", string(Int(TIMEOUT_SEC)))
        write_macro(io, "PalisadeBenchmarkInstances", string(length(unique([row.instance for row in rows]))))
        write_macro(io, "PalisadeBenchmarkFamilies", string(length(families(rows))))
        write_macro(io, "PalisadeCplexSolvedRatio", "$(cplex.solved)/$(cplex.total)")
        write_macro(io, "PalisadeHeuristicSolvedRatio", "$(heuristic.solved)/$(heuristic.total)")
        write_macro(io, "PalisadeHeuristicFirstTimeoutBoard", latex_board(heuristicTimeout.n, heuristicTimeout.m))
        write_macro(io, "PalisadeHeuristicFirstTimeoutCells", string(heuristicTimeout.N))
        write_macro(io, "PalisadeCplexLargestSolvedBoard", latex_board(cplexLargest.n, cplexLargest.m))
        write_macro(io, "PalisadeCplexLargestSolvedCells", string(cplexLargest.N))
        write_macro(io, "PalisadeCplexTimeoutBoard", latex_board(cplexTimeout.n, cplexTimeout.m))
        write_macro(io, "PalisadeCplexTimeoutCells", string(cplexTimeout.N))
        write_macro(io, "PalisadeSlowContrastInstance", latex_code(slow.instance))
        write_macro(io, "PalisadeFastContrastInstance", latex_code(fast.instance))
        write_macro(io, "PalisadeSlowContrastCplexTime", format_time(slow.solveTimeSec, slow.status))
        write_macro(io, "PalisadeFastContrastCplexTime", format_time(fast.solveTimeSec, fast.status))
    end
end

function write_family_table(rows, outputPath::String)
    open(outputPath, "w") do io
        println(io, "\\begin{table}[H]")
        println(io, "\\centering")
        println(io, "\\caption{Familles d'instances évaluées pour \\textit{Palisade}.}")
        println(io, "\\label{tab:palisade-families}")
        println(io, "\\begin{tabular}{lrrrrrr}")
        println(io, "\\toprule")
        println(io, "Famille & \$n\$ & \$m\$ & \$N\$ & \$k\$ & \$s\$ & Nombre d'instances\\\\")
        println(io, "\\midrule")
        for family in families(rows)
            println(io, latex_code(family.family), " & ", family.n, " & ", family.m, " & ", family.N, " & ", family.k, " & ", family.s, " & ", family.count, "\\\\")
        end
        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
        println(io, "\\end{table}")
    end
end

function write_performance_table(rows, outputPath::String)
    open(outputPath, "w") do io
        println(io, "\\begingroup")
        println(io, "\\small")
        println(io, "\\setlength{\\tabcolsep}{4pt}")
        println(io, "\\begin{table}[H]")
        println(io, "\\centering")
        println(io, "\\caption{Synthèse des performances par famille d'instances et par méthode.}")
        println(io, "\\label{tab:palisade-performance}")
        println(io, "\\begin{tabular}{llrrrr}")
        println(io, "\\toprule")
        println(io, "Famille & Méthode & Résolues / total & Timeouts & Temps moyen (s) & Temps maximal (s)\\\\")
        println(io, "\\midrule")

        for family in families(rows)
            for method in ("CPLEX", "Heuristique")
                currentRows = family_rows(rows, family.family, method)
                total = length(currentRows)
                solvedRows = [row for row in currentRows if row.status == "solved"]
                solved = length(solvedRows)
                timeouts = count(row -> row.status == "timeout", currentRows)
                meanText = isempty(solvedRows) ? "--" : format_float(mean([row.solveTimeSec for row in solvedRows]))
                maxText = isempty(solvedRows) ? "--" : format_float(maximum([row.solveTimeSec for row in solvedRows]))
                println(io, latex_code(family.family), " & ", method, " & ", solved, "/", total, " & ", timeouts, " & ", meanText, " & ", maxText, "\\\\")
            end
            println(io, "\\midrule")
        end

        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
        println(io, "\\end{table}")
        println(io, "\\endgroup")
    end
end

function write_contrast_table(rows, outputPath::String)
    selected = contrast_instances()

    open(outputPath, "w") do io
        println(io, "\\begingroup")
        println(io, "\\small")
        println(io, "\\setlength{\\tabcolsep}{4pt}")
        println(io, "\\begin{table}[H]")
        println(io, "\\centering")
        println(io, "\\caption{Instances contrastées de même taille : structure des indices et temps obtenus.}")
        println(io, "\\label{tab:palisade-contrast}")
        println(io, "\\begin{tabular}{lrrrrrrr}")
        println(io, "\\toprule")
        println(io, "Instance & \\#indices & Densité & \\#1 & \\#2 & \\#3 & Temps CPLEX (s) & Temps heuristique (s)\\\\")
        println(io, "\\midrule")

        for instance in selected
            cplexRow = contrast_instance(rows, instance, "CPLEX")
            heuristicRow = contrast_instance(rows, instance, "Heuristique")
            println(
                io,
                latex_code(instance), " & ",
                cplexRow.nbClues, " & ",
                format_density(cplexRow.clueDensity), " & ",
                cplexRow.nb1, " & ", cplexRow.nb2, " & ", cplexRow.nb3, " & ",
                format_time(cplexRow.solveTimeSec, cplexRow.status), " & ",
                format_time(heuristicRow.solveTimeSec, heuristicRow.status), "\\\\"
            )
        end

        println(io, "\\bottomrule")
        println(io, "\\end{tabular}")
        println(io, "\\end{table}")
        println(io, "\\endgroup")
    end
end

function contrast_instances()
    return [
        "gen_8x5_reg8_1",
        "gen_8x5_reg8_2",
        "gen_10x5_reg10_1",
        "gen_10x5_reg10_2",
    ]
end

function build_contrast_3d_figure(
    rows,
    selected::Vector{String},
    outputPath::String;
    methods::Vector{String} = ["CPLEX", "Heuristique"],
)
    selectedRows = [
        row for row in rows
        if row.instance in selected && row.method in methods
    ]
    plottedRows = [row for row in selectedRows if row.status == "solved"]
    maxZ = isempty(plottedRows) ? 1.0 : maximum(row.solveTimeSec for row in plottedRows)
    maxX = isempty(plottedRows) ? 1.0 : maximum(row.nb2 for row in plottedRows)
    maxY = isempty(plottedRows) ? 1.0 : maximum(row.nb1 + row.nb3 for row in plottedRows)

    p = plot(
        xaxis = "Nombre d'indices 2",
        yaxis = "Nb. d'indices 1 et 3",
        zaxis = "Temps (s)",
        legend = :topright,
        camera = (42, 24),
        xlims = (0, maxX + 2),
        ylims = (0, maxY + 2),
        zlims = (0, maxZ + max(1.0, 0.12 * maxZ)),
        size = (900, 620),
        right_margin = 16Plots.mm,
        guidefontsize = 9,
        tickfontsize = 8,
    )

    labelOffsets = Dict(
        "CPLEX" => (0.85, 0.35, 3.0),
        "Heuristique" => (-1.15, 0.65, 4.0),
    )

    for (method, marker, color) in [("CPLEX", :circle, :steelblue), ("Heuristique", :diamond, :darkorange)]
        methodRows = [row for row in plottedRows if row.method == method]
        xValues = [row.nb2 for row in methodRows]
        yValues = [row.nb1 + row.nb3 for row in methodRows]
        zValues = [row.solveTimeSec for row in methodRows]
        labels = [format_float(row.solveTimeSec) for row in methodRows]

        for i in eachindex(methodRows)
            plot!(
                p,
                [xValues[i], xValues[i]],
                [yValues[i], yValues[i]],
                [0.0, zValues[i]],
                label = "",
                color = color,
                alpha = 0.35,
                linewidth = 1.5,
                linestyle = :dash,
            )
            plot!(
                p,
                [0.0, xValues[i]],
                [yValues[i], yValues[i]],
                [0.0, 0.0],
                label = "",
                color = color,
                alpha = 0.18,
                linewidth = 1.1,
                linestyle = :dot,
            )
            plot!(
                p,
                [xValues[i], xValues[i]],
                [0.0, yValues[i]],
                [0.0, 0.0],
                label = "",
                color = color,
                alpha = 0.18,
                linewidth = 1.1,
                linestyle = :dot,
            )
        end

        scatter!(
            p,
            xValues,
            yValues,
            zValues,
            label = method,
            marker = marker,
            color = color,
            markersize = 7,
        )

        offsetX, offsetY, offsetZ = labelOffsets[method]
        annotate!(
            p,
            [
                begin
                    pointOffsetX = methodRows[i].instance == "gen_8x5_reg8_1" && method == "CPLEX" ? -2.25 : offsetX
                    pointOffsetY = methodRows[i].instance == "gen_8x5_reg8_1" && method == "CPLEX" ? 0.15 : offsetY + 0.25 * (i - 1)
                    (
                        xValues[i] + pointOffsetX,
                        yValues[i] + pointOffsetY,
                        min(zValues[i] + offsetZ, TIMEOUT_SEC),
                        text(labels[i], 8, color),
                    )
                end
                for i in eachindex(methodRows)
            ],
        )
    end

    savefig(p, outputPath)
end

function build_contrast_figures(rows)
    build_contrast_3d_figure(
        rows,
        ["gen_8x5_reg8_1", "gen_8x5_reg8_2"],
        joinpath(IMAGE_DIR, "palisade_contrast_indices_8x5_3d.pdf"),
        methods = ["CPLEX"],
    )
    build_contrast_3d_figure(
        rows,
        ["gen_10x5_reg10_1", "gen_10x5_reg10_2"],
        joinpath(IMAGE_DIR, "palisade_contrast_indices_10x5_3d.pdf"),
    )
end

function build_region_figure(rows, outputPath::String)
    regionRows = [row for row in rows if row.n == 6 && row.m == 6]
    kValues = sort(unique([row.k for row in regionRows]))

    p = plot(
        xaxis = "Nombre de régions",
        yaxis = "Temps (s)",
        yscale = :log10,
        legend = :topleft,
        size = (850, 450),
    )

    for (method, offset, color) in [("CPLEX", -0.08, :steelblue), ("Heuristique", 0.08, :darkorange)]
        methodRows = [row for row in regionRows if row.method == method]
        scatter!(p, [row.k + offset for row in methodRows], [row.solveTimeSec for row in methodRows], label = method, color = color, markersize = 7)

        meanTimes = [
            mean([row.solveTimeSec for row in methodRows if row.k == currentK])
            for currentK in kValues
        ]
        plot!(p, [currentK + offset for currentK in kValues], meanTimes, label = "", color = color, linewidth = 2)
    end

    hline!(p, [TIMEOUT_SEC], label = "Limite", color = :black, linestyle = :dash)
    savefig(p, outputPath)
end

function generate_report_artifacts()
    mkpath(GENERATED_DIR)
    mkpath(IMAGE_DIR)

    obsoleteFiles = [
        joinpath(GENERATED_DIR, "palisade_summary.csv"),
        joinpath(GENERATED_DIR, "palisade_table_detailed.tex"),
        joinpath(IMAGE_DIR, "palisade_resolution_rate.pdf"),
        joinpath(IMAGE_DIR, "palisade_size_scatter.pdf"),
        joinpath(IMAGE_DIR, "palisade_indices_effect.pdf"),
        joinpath(IMAGE_DIR, "palisade_contrast_indices_3d.pdf"),
    ]

    for path in obsoleteFiles
        rm(path; force=true)
    end

    rows = build_rows()

    write_macros(rows, joinpath(GENERATED_DIR, "palisade_analysis_macros.tex"))
    write_family_table(rows, joinpath(GENERATED_DIR, "palisade_table_families.tex"))
    write_performance_table(rows, joinpath(GENERATED_DIR, "palisade_table_performance.tex"))
    write_contrast_table(rows, joinpath(GENERATED_DIR, "palisade_table_contrasts.tex"))

    performanceDiagram(joinpath(IMAGE_DIR, "palisade_performance_diagram.pdf"); generatedOnly=true)
    resultsArray(joinpath(GENERATED_DIR, "palisade_results_array.tex"); generatedOnly=true)
    build_region_figure(rows, joinpath(IMAGE_DIR, "palisade_regions_6x6.pdf"))
    build_contrast_figures(rows)

    println("Palisade report artifacts written to ", GENERATED_DIR, " and ", IMAGE_DIR)
end

if abspath(PROGRAM_FILE) == @__FILE__
    generate_report_artifacts()
end
