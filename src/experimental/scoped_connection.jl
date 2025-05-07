### scoped_connection.jl
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
# This file contains implementation of simplified interface utilizing connection as dynamically scoped variable.
#
### Code:

const sconnection = ScopedValue{Connection}()

function scoped_connection()
    conn = ScopedValues.get(sconnection)
    if isnothing(conn)
        error("""No scoped connection.
            To use methods without explicit `connection` parameter you need to wrap your logic into `with_connection` function.
            
            Example:
            ```
            nc = NATS.connect()
            with_connection(nc) do
                publish("some_subject", "Some payload")
            end
            ```

            Or pass `connection` explicitly:
            ```
            nc = NATS.connect()
            publish(nc, "some_subject", "Some payload")
            ```
            """)
    end
    conn.value
end

"""
$(SIGNATURES)

Create scope with ambient context connection, in which connection argument might be skipped during invocation of functions.

Usage:
```
    nc = NATS.connect()
    with_connection(nc) do
        publish("some.subject") # No `connection` argument.
    end
```
"""
function with_connection(f, nc::Connection)
    with(f, sconnection => nc)
end

function subscribe(
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    channel_size = parse(Int64, get(ENV, "NATS_SUBSCRIPTION_CHANNEL_SIZE", string(DEFAULT_SUBSCRIPTION_CHANNEL_SIZE))),
    monitoring_throttle_seconds = parse(Float64, get(ENV, "NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS", string(DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS)))
)
    subscribe(scoped_connection(), subject; queue_group, channel_size, monitoring_throttle_seconds)
end

function subscribe(
    f,
    subject::String;
    queue_group::Union{String, Nothing} = nothing,
    spawn = false,
    channel_size = parse(Int64, get(ENV, "NATS_SUBSCRIPTION_CHANNEL_SIZE", string(DEFAULT_SUBSCRIPTION_CHANNEL_SIZE))),
    monitoring_throttle_seconds = parse(Float64, get(ENV, "NATS_SUBSCRIPTION_ERROR_THROTTLING_SECONDS", string(DEFAULT_SUBSCRIPTION_ERROR_THROTTLING_SECONDS)))
)
    subscribe(f, scoped_connection(), subject; queue_group, spawn, channel_size, monitoring_throttle_seconds)
end

function unsubscribe(
    sub::Sub;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sub; max_msgs)
end

function unsubscribe(
    sid::Int64;
    max_msgs::Union{Int, Nothing} = nothing
)
    unsubscribe(scoped_connection(), sid; max_msgs)
end

function drain(sub::Sub)
    drain(scoped_connection(), sub)
end

function publish(
    subject::String,
    data = nothing;
    reply_to::Union{String, Nothing} = nothing
)
    publish(scoped_connection(), subject, data; reply_to)
end

function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    spawn = false
)
    reply(f, scoped_connection(), subject; queue_group, spawn)
end

function request(
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    request(scoped_connection(), subject, data; timeout)
end

function request(
    nreplies::Integer,
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    request(scoped_connection(), nreplies, subject, data; timeout)
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    timeout::Union{Real, Period} = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(DEFAULT_REQUEST_TIMEOUT_SECONDS)))
)
    request(T, scoped_connection(), subject, data; timeout)
end

function next(sub::Sub; no_wait = false, no_throw = false)::Union{Msg, Nothing}
    next(scoped_connection(), sub::Sub; no_wait = false, no_throw = false)
end

function next(T::Type, sub::Sub; no_wait = false, no_throw = false)::Union{T, Nothing}
    next(T, scoped_connection(), sub::Sub; no_wait = false, no_throw = false)
end

function next(sub::Sub, batch::Integer; no_wait = false, no_throw = false)::Vector{Msg}
    next(scoped_connection(), sub, batch; no_wait = false, no_throw = false)
end

function next(T::Type, sub::Sub, batch::Integer; no_wait = false, no_throw = false)::Vector{T}
    next(T, scoped_connection(), sub, batch; no_wait = false, no_throw = false)
end

@testitem "Scoped connections" setup=[GetConnection] begin
    @test_throws ErrorException publish("some.random.subject")

    was_delivered = Ref(false)
    with_connection(nc) do 
        sub = subscribe("subject_1") do msg
            was_delivered[] = true
        end
        publish("subject_1")
        publish("subject_1", "Some data")
        drain(sub)
    end
    @test was_delivered[] == true

    with_connection(nc) do 
        sub = reply("service_1") do 
            "Response content"
        end
        answer = request("service_1")
        @test payload(answer) == "Response content"
        answer = request(String, "service_1")
        @test answer == "Response content"
        sub2 = reply("service_1") do 
            "Response content 2"
        end
        answers = request(2, "service_1", nothing)
        @test length(answers) == 2
        drain(sub)
        drain(sub2)
    end
    drain(nc)
    nc = NATS.connect()
    with_connection(nc) do 
        sub1 = reply("some_service") do 
            "Response content"
        end
        sub2 = reply("some_service") do 
            "Response content"
        end
        unsubscribe(sub1)
        unsubscribe(sub2.sid)
    end
    drain(nc)
end

@testitem "Scoped connections sync subscriptions" setup=[GetConnection] begin
    using JSON3

    with_connection(nc) do 
        sub = subscribe("subject_1")

        publish("subject_1", "test")
        msg = next(sub)
        @test msg isa NATS.Msg
        
        publish("subject_1", "{}")
        msg = next(JSON3.Object, sub)
        @test msg isa JSON3.Object

        publish("subject_1", "test")
        msgs = next(sub, 1)
        @test msgs isa Vector{NATS.Msg}
        @test length(msgs) == 1

        publish("subject_1", "{}")
        jsons = next(JSON3.Object, sub, 1)
        @test jsons isa Vector{JSON3.Object}
        @test length(jsons) == 1

        drain(sub)
    end
end
