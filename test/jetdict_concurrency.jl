# Run without a server: julia --project=. test/jetdict_concurrency.jl
using Test

@testset "JetDict optimistic concurrency" begin
    # Keep response doubles out of the connected tests, and exercise multiple
    # threads even when the parent test process has only one default thread.
    regression = joinpath(@__DIR__, "jetdict_concurrency_probe.jl")
    @test success(`$(Base.julia_cmd()) --startup-file=no --threads=4 --project=$(dirname(@__DIR__)) $regression`)
end
