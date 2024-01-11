### connection.jl
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
# This file contains data structure definitions and aggregates utilities for handling connection to NATS server.
#
### Code:

@enum ConnectionStatus CONNECTING CONNECTED DISCONNECTED DRAINING DRAINED

include("stats.jl")

const DEFAULT_SEND_BUFFER_LIMIT_BYTES = 2 * 2^20 # TODO: rename to limit
const SEND_RETRY_DELAYS = Base.ExponentialBackOff(n=53, first_delay=0.01, max_delay=0.1)

struct SubscriptionData
    sub::Sub
    channel::Channel
    stats::Stats
end

@kwdef mutable struct Connection
    url::String
    status::ConnectionStatus = CONNECTING
    stats::Stats = Stats()
    info::Union{Info, Nothing}
    sub_data::Dict{String, SubscriptionData} = Dict{String, SubscriptionData}()
    unsubs::Dict{String, Int64} = Dict{String, Int64}()
    lock::ReentrantLock = ReentrantLock()
    rng::AbstractRNG = MersenneTwister()
    send_buffer::IO = IOBuffer()
    send_buffer_cond::Threads.Condition = Threads.Condition()
    send_buffer_limit::Int64 = DEFAULT_SEND_BUFFER_LIMIT_BYTES
    send_retry_delays::Any = SEND_RETRY_DELAYS
    send_enqueue_when_disconnected::Bool
    reconnect_event::Threads.Event = Threads.Event()
    drain_event::Threads.Event = Threads.Event()
    pong_received_cond::Threads.Condition = Threads.Condition()
    status_change_cond::Threads.Condition = Threads.Condition()
    @atomic connect_init_count::Int64 # How many tries of protocol init was done on last reconnect.
    @atomic reconnect_count::Int64
    @atomic send_buffer_flushed::Bool
    drain_timeout::Float64
    drain_poll::Float64
end

info(c::Connection)::Union{Info, Nothing} = @lock c.lock c.info
info(c::Connection, info::Info) = @lock c.lock c.info = info
status(c::Connection)::ConnectionStatus = @lock c.status_change_cond c.status
function status(c::Connection, status::ConnectionStatus)
    @lock c.status_change_cond begin
        c.status = status
        notify(c.status_change_cond)
    end
end

function clustername(c::Connection)
    info_msg = info(c)
    if isnothing(info_msg)
        "unknown"
    else
        @something info(c).cluster "unnamed"
    end
end

function new_inbox(connection::Connection, prefix::String = "inbox.")
    random_suffix = @lock connection.lock randstring(connection.rng, 10)
    "inbox.$random_suffix"
end

function new_sid(connection::Connection)
    @lock connection.lock randstring(connection.rng, 6)
end

include("state.jl")
include("utils.jl")
include("tls.jl")
include("send.jl")
include("handlers.jl")
include("drain.jl")
include("connect.jl")

function status()
    println("=== Connection status ====================")
    println("connections:    $(length(state.connections))        ")
    for (i, nc) in enumerate(state.connections)
        print("       [#$i]:  ")
        print(status(nc), ", " , length(nc.sub_data)," subs, ", length(nc.unsubs)," unsubs             ")
        println()
    end
    # println("subscriptions:  $(length(state.handlers))           ")
    println("msgs_handled:   $(state.stats.msgs_handled)         ")
    println("msgs_errored:   $(state.stats.msgs_errored)        ")
    println("==========================================")
end

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    clustername(nc), " cluster", ", " , status(nc), ", " , length(nc.sub_data)," subs, ", length(nc.unsubs)," unsubs)")

function ping(nc; timer = Timer(1.0))
    pong_ch = Channel{Pong}(1)
    ping_task = @async begin
        @async send(nc, Ping())
        @lock nc.pong_received_cond wait(nc.pong_received_cond)
        put!(pong_ch, Pong())
    end

    @async begin
        try wait(timer) catch end
        close(pong_ch)
    end
    try
        take!(pong_ch)
    catch
        error("No PONG received.")
    end
end
