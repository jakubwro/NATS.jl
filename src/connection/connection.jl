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

const DEFAULT_SEND_BUFFER_SIZE = 2 * 2^20
const SEND_RETRY_DELAYS = Base.ExponentialBackOff(n=200, first_delay=0.01, max_delay=0.1)

@kwdef mutable struct Connection
    host::String
    port::Int64
    status::ConnectionStatus = CONNECTING
    stats::Stats = Stats()
    info::Info
    reconnect_count::Int64 = 0
    lock::ReentrantLock = ReentrantLock()
    rng::AbstractRNG = MersenneTwister()
    subs::Dict{String, Sub} = Dict{String, Sub}()
    unsubs::Dict{String, Int64} = Dict{String, Int64}()
    send_buffer::IO = IOBuffer()
    send_buffer_cond::Threads.Condition = Threads.Condition()
    send_buffer_size::Int64 = DEFAULT_SEND_BUFFER_SIZE
    send_retry_delays::Any = SEND_RETRY_DELAYS
end

info(c::Connection)::Info = @lock c.lock c.info
info(c::Connection, info::Info) = @lock c.lock c.info = info
clustername(c::Connection) = @something info(c).cluster "unnamed"
status(c::Connection)::ConnectionStatus = @lock c.lock c.status
status(c::Connection, status::ConnectionStatus) = @lock c.lock c.status = status

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
        print(status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs             ")
        println()
    end
    println("subscriptions:  $(length(state.handlers))           ")
    println("msgs_handled:   $(state.stats.msgs_handled)         ")
    println("msgs_errored:   $(state.stats.msgs_errored)        ")
    println("==========================================")
end

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    clustername(nc), " cluster", ", " , status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs)")

function ping(nc)
    send(nc, Ping())
end
