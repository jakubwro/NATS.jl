
using Test
using NATS
using Random

@testset "Publish subscribe" begin
    c = Channel()
    sub = subscribe(nc, "SOME.BAR") do msg
        put!(c, msg)
    end
    publish(nc, "SOME.BAR", "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(nc.sub_data) == 1
    drain(nc, sub)
    @test length(nc.sub_data) == 0
end

NATS.status()

@testset "Publish subscribe with sync handlers" begin
    connection = NATS.connect()
    c = Channel()
    sub = subscribe(connection, "SOME.BAR") do msg
        put!(c, msg)
    end
    publish(connection, "SOME.BAR", "Hi!")
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test length(connection.sub_data) == 1
    drain(connection, sub)
    @test length(connection.sub_data) == 0

    c = Channel()
    sub = subscribe(connection, "SOME.BAR") do msg::String
        put!(c, msg)
    end
    publish(connection, "SOME.BAR", "Hi!")
    result = take!(c)
    drain(connection, sub)
    @test result == "Hi!"
end

NATS.status()

@testset "Typed subscription handlers" begin
    c = Channel()

    sub = subscribe(nc, "SOME.BAR") do msg::String
        put!(c, msg)
    end
    publish(nc, "SOME.BAR", "Hi!")
    result = take!(c)
    @test result == "Hi!"
    @test length(nc.sub_data) == 1
    drain(nc, sub)
    @test length(nc.sub_data) == 0
end

NATS.status()

@testset "Publish subscribe with headers" begin
    c = Channel()
    sub = subscribe(nc, "SOME.BAR") do msg
        put!(c, msg)
    end
    publish(nc, "SOME.BAR", ("Hi!", ["A" => "B"]))
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test headers(result) == ["A" => "B"]
    @test length(nc.sub_data) == 1
    drain(nc, sub)
    @test length(nc.sub_data) == 0
end

NATS.status()

@testset "Subscription without argument" begin
    subject = randstring(8)
    was_delivered = false
    sub = subscribe(nc, subject) do
        was_delivered = true
        "nothing to do"
    end
    publish(nc, subject, "Hi!")
    drain(nc, sub)
    @test was_delivered
end

NATS.status()

@testset "Subscription with multiple arguments" begin
    subject = randstring(8)
    # TODO: test if error message is clear.
    @test_throws ErrorException subscribe(nc, subject) do x, y, z
        "nothing to do"
    end
end

NATS.status()
