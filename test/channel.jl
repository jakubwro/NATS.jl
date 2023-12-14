using Test
using NATS

try
    NATS.connect(default = true)
catch
    @info "Default conneciton already exists."
end

@testset "Single message" begin
    ch = NATSChannel{String}(subject = "channel_subject")
    @async put!(ch, "Simple payload")
    res = take!(ch)
    @test res == "Simple payload"
end

@testset "Test blocking" begin
    ch = NATSChannel{String}(subject = "channel_subject")
    
    @async put!(ch, "This is test")
    sleep(3)
    res = take!(ch)
    @test res == "This is test"

    res = nothing
    t = @async begin
        res = take!(ch)
    end
    sleep(3)
    put!(ch, "Another test")
    wait(t)
    @test res == "Another test"
end

@testset "1K messages put! first" begin
    ch = NATSChannel{String}(subject = "channel_subject")
    n=1000
    for i in 1:n
        @async put!(ch, "$i")
    end
    results = String[]
    @sync for i in 1:n
        @async begin 
            res = take!(ch)
            push!(results, res)
        end
    end
    @test length(results) == n
    for i in 1:n
        @test "$i" in results
    end
end

@testset "1K messages take! first" begin
    ch = NATSChannel{String}(subject = "channel_subject")
    n = 1000
    results = String[]
    for i in 1:n
        @async begin 
            res = take!(ch)
            push!(results, res)
        end
    end
    @sync for i in 1:n
        @async put!(ch, "$i")
    end
    @test length(results) == n
    for i in 1:n
        @test "$i" in results
    end
end

@testset "Multiple connections" begin
    conn1 = NATS.connect()
    conn2 = NATS.connect()
    conn3 = NATS.connect()
    conn4 = NATS.connect()
    conn5 = NATS.connect()
    ch1 = NATSChannel{String}(subject = "channel_subject", connection = conn1)
    ch2 = NATSChannel{String}(subject = "channel_subject", connection = conn2)
    ch3 = NATSChannel{String}(subject = "channel_subject", connection = conn3)
    ch4 = NATSChannel{String}(subject = "channel_subject", connection = conn4)
    ch5 = NATSChannel{String}(subject = "channel_subject", connection = conn5)
    for i in 1:15
        @async put!(ch1, "$i")
    end
    for i in 1:15
        @async put!(ch2, "$(15 + i)")
    end
    lk = ReentrantLock()
    results = String[]
    for i in 1:10
        @async begin 
            res = take!(ch3)
            @lock lk push!(results, res)
        end
    end
    for i in 1:10
        @async begin 
            res = take!(ch4)
            @lock lk push!(results, res)
        end
    end
    for i in 1:10
        @async begin 
            res = take!(ch5)
            @lock lk push!(results, res)
        end
    end

    sleep(2)
    @test length(results) == 30
    for i in 1:30
        @test "$i" in results
    end
end

