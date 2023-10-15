

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

include("stats.jl")

@kwdef mutable struct Connection
    host::String
    port::Int64
    status::ConnectionStatus = CONNECTING
    stats::Stats = Stats()
    info::Info
    outbox::Channel{ProtocolMessage}
    reconnect_count::Int64 = 0
    lock::ReentrantLock = ReentrantLock()
    rng::AbstractRNG = MersenneTwister()
    subs::Dict{String, Sub} = Dict{String, Sub}()
    unsubs::Dict{String, Int64} = Dict{String, Int64}()
end

info(c::Connection)::Info = @lock c.lock c.info
info(c::Connection, info::Info) = @lock c.lock c.info = info
clustername(c::Connection) = @something info(c).cluster "unnamed"
status(c::Connection)::ConnectionStatus = @lock c.lock c.status
status(c::Connection, status::ConnectionStatus) = @lock c.lock c.status = status
outbox(c::Connection) = @lock c.lock c.outbox
outbox(c::Connection, ch::Channel{ProtocolMessage}) = @lock c.lock c.outbox = ch

function new_inbox(connection::Connection, prefix::String = "")
    random_suffix = @lock connection.lock randstring(connection.rng, 10)
    if !isnothing(prefix) && !isempty(prefix)
        "$prefix.$random_suffix"
    else
        "inbox.$random_suffix"
    end
end

function new_sid(connection::Connection)
    @lock connection.lock randstring(connection.rng, 20)
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
    println("msgs_errored:   $(state.stats.msgs_errored)        ")
    println("==========================================")
end

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    clustername(nc), " cluster", ", " , status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

function ping(nc)
    send(nc, Ping())
end
