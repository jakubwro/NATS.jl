using Test
using NATS

try
    NATS.connect(default = true)
catch
    @info "Default conneciton already exists."
end

@testset "Channel basic tests" begin
    ch = NATSChannel{String}(subject = "channel_subject")
    @async put!(ch, "Simple payload")
    res = take!(ch)
    @test res == "Simple payload"
end

@testset "1K messages" begin
    ch = NATSChannel{String}(subject = "channel_subject")

    for i in 1:1000
        @async put!(ch, "$i")
    end

    results = String[]
    @sync for i in 1:1000
        @async begin 
            res = take!(ch)
            push!(results, res)
        end
    end

    @test length(results) == 1000
    for i in 1:1000
        @test "$i" in results
    end
end
