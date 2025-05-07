### pubsub.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains aggregates utils for publish - subscribe pattern.
#
### Code:

include("publish.jl")
include("subscribe.jl")
include("unsubscribe.jl")
include("drain.jl")

@testitem "Publish subscribe" setup=[GetConnection] begin
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

@testitem "Publish subscribe with sync handlers" setup=[GetConnection] begin
    nc = NATS.connect()
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

    c = Channel()
    sub = subscribe(nc, "SOME.BAR") do msg::String
        put!(c, msg)
    end
    publish(nc, "SOME.BAR", "Hi!")
    result = take!(c)
    drain(nc, sub)
    @test result == "Hi!"
end

@testitem "Typed subscription handlers" setup=[GetConnection] begin
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

@testitem "Publish subscribe with headers" setup=[GetConnection] begin
    c = Channel()
    sub = subscribe(nc, "SOME.BAR2") do msg
        put!(c, msg)
    end
    publish(nc, "SOME.BAR2", ("Hi!", ["A" => "B"]))
    result = take!(c)
    @test result isa NATS.Msg
    @test payload(result) == "Hi!"
    @test headers(result) == ["A" => "B"]
    @test length(nc.sub_data) == 1
    drain(nc, sub)
    @test length(nc.sub_data) == 0
end

@testitem "Subscription without argument" setup=[GetConnection] begin
    using Random

    subject = randstring(8)
    was_delivered = Ref(false)
    sub = subscribe(nc, subject) do
        was_delivered[] = true
        "nothing to do"
    end
    publish(nc, subject, "Hi!")
    drain(nc, sub)
    @test was_delivered[]
end

@testitem "Subscription with multiple arguments" setup=[GetConnection] begin
    using Random

    subject = randstring(8)

    @test_throws "Conversion of NATS message into type Tuple{Any, Any, Any} is not defined" subscribe(nc, subject) do x, y, z
        "nothing to do"
    end

    received_payload = Ref{Any}(nothing)
    received_headers = Ref{Any}(nothing)
    sub = subscribe(nc, subject) do msg::String, hdr::NATS.Headers
        received_payload[] = msg
        received_headers[] = hdr
    end
    publish(nc, subject, ("data", ["x" => "y"]))
    sleep(0.2)
    @test received_payload[] == "data"
    @test received_headers[] isa NATS.Headers
    @test received_headers[][1] == Pair("x", "y")
    drain(nc, sub)
end

@testitem "Synchronous subscriptions" setup=[GetConnection] begin
    using Random, JSON3

    subject = randstring(8)
    sub = subscribe(nc, subject)
    
    msg = next(nc, sub; no_wait = true)
    @test isnothing(msg)

    @async begin
        for i in 1:100
            sleep(0.01)
            publish(nc, subject, """{"x": 1}""")
        end
        sleep(0.2)
        unsubscribe(nc, sub)
    end

    msg = next(nc, sub)
    @test msg isa NATS.Msg

    json = next(JSON3.Object, nc, sub)
    @test json.x == 1

    msgs = next(nc, sub, 10)
    @test msgs isa Vector{NATS.Msg}
    @test length(msgs) == 10

    jsons = next(JSON3.Object, nc, sub, 10)
    @test length(jsons) == 10

    sleep(2)

    msgs = next(nc, sub, 78)
    @test msgs isa Vector{NATS.Msg}
    @test length(msgs) == 78

    msgs = next(nc, sub, 100; no_wait = true, no_throw = true)
    @test msgs isa Vector{NATS.Msg}
    @test length(msgs) == 0

    jsons = next(JSON3.Object, nc, sub, 100; no_throw = true, no_wait = true)
    @test msgs isa Vector{NATS.Msg}
    @test length(jsons) == 0

    @test_throws "Client unsubscribed" next(nc, sub)
    @test_throws "Client unsubscribed" next(JSON3.Object, nc, sub)
    @test_throws "Client unsubscribed" next(nc, sub; no_wait = true)
    @test_throws "Client unsubscribed" next(JSON3.Object, nc, sub)
    @test_throws "Client unsubscribed" next(nc, sub, 2)
    @test_throws "Client unsubscribed" next(JSON3.Object, nc, sub, 2)
    @test isnothing(next(nc, sub; no_throw = true, no_wait = true))
end

@testitem "10k subscriptions" begin
    using Random

    n_subs = 10000
    n_pubs = 10
    subject = randstring(8)
    subject_ack = randstring(8)
    ch = Channel(Inf)
    sub_nc = NATS.connect()
    for i in 1:n_subs
        subscribe(sub_nc, subject) do msg
            put!(ch, msg)
            publish(sub_nc, subject_ack, "ack")
        end
    end
    sleep(5)

    pub_nc = NATS.connect()
    ack_count = Threads.Atomic{Int64}(0)
    subscribe(pub_nc, subject_ack) do msg
        Threads.atomic_add!(ack_count, 1)
    end
    sleep(5)

    for i in 1:n_pubs
        publish(pub_nc, subject, "Test 10k subs: msg $i.")
    end
    sleep(10)
    drain(sub_nc)
    drain(pub_nc)
    sub_stats = NATS.stats(sub_nc)
    pub_stats = NATS.stats(pub_nc)
    @test ack_count.value == n_pubs  * n_subs
    @test Base.n_avail(ch) == n_pubs * n_subs
    @test sub_stats.msgs_handled == n_pubs  * n_subs
    @test sub_stats.msgs_published == n_pubs  * n_subs
    @test pub_stats.msgs_handled == n_pubs  * n_subs
    @test pub_stats.msgs_published == n_pubs
end
