

# """
# digraph G {
#   connecting   -> connected
#   connecting   -> disconnected
#   connected    -> connecting
#   connected    -> draining
#   draining     -> drained
# }
# """
@enum ConnectionStatus CONNECTING CONNECTED DISCONNECTED DRAINING DRAINED

@kwdef mutable struct Stats
    msgs_handled::Int64 = 0
    msgs_not_handled::Int64 = 0
    reconnections::Int64 = 0
end

@kwdef struct SubStats
    # "Seconds since the epoch."
    # time_created::Float64
    "Count of msgs handled without error."
    msgs_handled::Int64 = 0
    "Count of msgs that caused handler function error."
    msgs_errored::Int64 = 0
    "Msgs that was not put to the channel because it was full."
    msgs_dropped::Int64 = 0
    "Total handlers running at the moment."
    handers_running::Int64 = 0
    "Function that can be installed to monitor handler errors."
    error_handler::Function = nothing
end

@kwdef mutable struct Connection
    host::String
    port::Int64
    status::ConnectionStatus = CONNECTING
    info::Info
    outbox::Channel{ProtocolMessage}
    subs::Dict{String, Sub} = Dict{String, Sub}()
    unsubs::Dict{String, Int64} = Dict{String, Int64}()
    stats::Stats = Stats()
    rng::AbstractRNG = MersenneTwister()
    lock::ReentrantLock = ReentrantLock()
end

info(c::Connection)::Info = @lock c.lock c.info
info(c::Connection, info::Info) = @lock c.lock c.info = info
clustername(c::Connection) = @something info(c).cluster "unnamed"
status(c::Connection)::ConnectionStatus = @lock c.lock c.status
status(c::Connection, status::ConnectionStatus) = @lock c.lock c.status = status
outbox(c::Connection) = @lock c.lock c.outbox
outbox(c::Connection, ch::Channel{ProtocolMessage}) = @lock c.lock c.outbox = ch

mutable struct State
    default_connection::Union{Connection, Nothing}
    connections::Vector{Connection}
    handlers::Dict{String, Channel}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
end

function connection(id::Symbol)
    if id === :default
        nc = @lock state.lock state.default_connection
        isnothing(nc) && error("No default connection availabe. Call `NATS.connect(default = true)` before.")
        nc
    else
        error("Connection `:$id` does not exits.")
    end
end

function connection(id::Symbol, nc::Connection)
    if id === :default
        @lock state.lock state.default_connection = nc
    else
        error("Cannot set connection `:$id`, expected `:default`.")
    end
end

function connection(id::Integer)
    if id in 1:length(state.connections)
        state.connections[id]
    else
        error("Connection #$id does not exists.")
    end
end

include("utils.jl")
include("tls.jl")
include("nkeys.jl")
include("send.jl")
include("handlers.jl")
include("drain.jl")
include("connect.jl")

const state = State(nothing, Connection[], Dict{String, Function}(), Function[default_fallback_handler], ReentrantLock(), Stats())

function status()
    println("=== Connection status ====================")
    println("connections:    $(length(state.connections))        ")
    if !isnothing(state.default_connection)
        print("  [default]:  ")
        nc = state.default_connection
        print(status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox             ")
        println()
    end
    for (i, nc) in enumerate(state.connections)
        print("       [#$i]:  ")
        print(status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox             ")
        println()
    end
    println("subscriptions:  $(length(state.handlers))           ")
    println("msgs_handled:   $(state.stats.msgs_handled)         ")
    println("msgs_unhandled: $(state.stats.msgs_not_handled)        ")
    println("==========================================")
end

# show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
#     status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

# """
# Enqueue protocol message in `outbox` to be written to socket.
# """

function ping(nc)
    send(nc, Ping())
end

# """
# Cleanup subscription data when no more messages are expected.
# """
function _cleanup_sub(nc::Connection, sid::String)
    lock(state.lock) do
        ch = get(state.handlers, sid, nothing)
        !isnothing(ch) && close(ch)
        delete!(state.handlers, sid)
        delete!(nc.subs, sid)
        delete!(nc.unsubs, sid)
    end
end

# """
# Update state on message received.
# """
function _cleanup_unsub_msg(nc::Connection, sid::String)
    lock(state.lock) do
        count = get(nc.unsubs, sid, nothing)
        if !isnothing(count)
            count = count - 1
            if count == 0
                _cleanup_sub(nc, sid)
            else
                nc.unsubs[sid] = count
            end
        end
    end
end
