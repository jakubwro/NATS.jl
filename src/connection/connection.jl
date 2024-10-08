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

struct SubscriptionData
    sub::Sub
    channel::Channel
    stats::Stats
    is_async::Bool
    lock::ReentrantLock
end

@kwdef mutable struct Connection
    url::String
    status::ConnectionStatus = CONNECTING
    stats::Stats = Stats()
    info::Union{Info, Nothing}
    sub_data::Dict{Int64, SubscriptionData} = Dict{Int64, SubscriptionData}()
    unsubs::Dict{Int64, Int64} = Dict{Int64, Int64}()
    lock::ReentrantLock = ReentrantLock()
    rng::AbstractRNG = MersenneTwister()
    last_sid::Int64 = 0
    send_buffer::IO = IOBuffer()
    send_buffer_cond::Threads.Condition = Threads.Condition()
    send_buffer_limit::Int64 = DEFAULT_SEND_BUFFER_LIMIT_BYTES
    send_retry_delays::Any = SEND_RETRY_DELAYS
    send_enqueue_when_disconnected::Bool
    reconnect_event::Threads.Event = Threads.Event()
    drain_event::Threads.Event = Threads.Event()
    @atomic pong_count::Int64
    @atomic pong_received_at::Float64
    status_change_cond::Threads.Condition = Threads.Condition()
    @atomic connect_init_count::Int64 # How many tries of protocol init was done on last reconnect.
    @atomic reconnect_count::Int64
    @atomic send_buffer_flushed::Bool
    drain_timeout::Float64
    drain_poll::Float64
    allow_direct::Dict{String, Bool} = Dict{String, Bool}() # Cache for jetstream for fast lookup of streams that have direct access.
    allow_direct_lock = ReentrantLock()
    "Handles messages for which handler was not found."
    fallback_handlers::Vector{Function} = Function[]
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
    @lock connection.lock begin
        connection.last_sid += 1
        connection.last_sid 
    end
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

function ping(nc; timeout::Union{Real, Period} = 1.0, measure = true)
    last_pong_count = @atomic nc.pong_count
    start_time = time()
    send(nc, Ping())
    result = timedwait(timeout; pollint = 0.001) do
        (@atomic nc.pong_count) != last_pong_count
    end
    result == :timed_out && error("No PONG received in specified timeout ($timeout seconds).")
    result == :ok || error("Unexpected status symbol: :$result")
    if measure && (@atomic nc.pong_received_at) > 0.0
        @info "Measured ping time is $(1000 * ((@atomic nc.pong_received_at) - start_time)) milliseconds"
    end
    Pong()
end

function stats(connection::Connection)
    connection.stats
end

function stats(connection::Connection, sid::Int64)
    sub_data = @lock connection.lock get(connection.sub_data, sid, nothing)
    isnothing(sub_data) && return
    sub_data.stats
end

function stats(connection::Connection, sub::Sub)
    stats(connection, sub.sid)
end

function status_change(f, nc::Connection)
    while true
        st = status(nc)
        if st == DRAINED
            break
        end
        @lock nc.status_change_cond begin
            wait(nc.status_change_cond)
            st = nc.status
        end
        f(st)
    end
end
