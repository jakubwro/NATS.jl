

# """
# digraph G {
#   connecting   -> connected
#   connected    -> reconnecting
#   reconnecting -> connected
#   connected    -> draining
#   draining     -> drained
# }
# """
@enum ConnectionStatus CONNECTING CONNECTED RECONNECTING DRAINING DRAINED

mutable struct Stats
    msgs_handled::Int64
    msgs_not_handled::Int64
end

mutable struct Connection
    status::ConnectionStatus
    info::Channel{Info}
    outbox::Channel{ProtocolMessage}
    subs::Dict{String, Sub}
    unsubs::Dict{String, Int64}
    stats::Stats
    rng::AbstractRNG
    function Connection()
        new(CONNECTING, Channel{Info}(10), Channel{ProtocolMessage}(OUTBOX_SIZE), Dict{String, Sub}(), Dict{String, Int64}(), Stats(0, 0), MersenneTwister())
    end
end

mutable struct State
    default_connection::Union{Connection, Nothing}
    connections::Vector{Connection}
    handlers::Dict{String, Channel}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
end

include("utils.jl")
include("tls.jl")
include("send.jl")
include("handlers.jl")
include("reconnect.jl")

const state = State(nothing, Connection[], Dict{String, Function}(), Function[default_fallback_handler], ReentrantLock(), Stats(0, 0))

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

function default_connection()
    if isnothing(state.default_connection)
        error("No default connection availabe. Call `NATS.connect(default = true)` before.")
    end
    state.default_connection
end

# info(nc::Connection) = fetch(nc.info)
status(nc::Connection) = @lock state.lock nc.status
outbox(nc::Connection) = @lock state.lock nc.outbox

# show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
#     status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

# """
# Enqueue protocol message in `outbox` to be written to socket.
# """

#TODO: restore link #NATS.Connect
"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See `Connect protocol message`.
"""
function connect(host::String = NATS_HOST, port::Int = NATS_PORT; default = true, kw...)
    if default && !isnothing(state.default_connection)
        return default_connection()
    end
    nc = Connection()
    connect_msg = from_kwargs(Connect, DEFAULT_CONNECT_ARGS, kw)
    reconnect_task = Threads.Task(() ->  while true reconnect(nc, host, port, connect_msg) end)
    # Setting sticky flag to false makes processing 10x slower when running with multiple threads.
    # reconnect_task.sticky = false
    Base.Threads._spawn_set_thrpool(reconnect_task, :default)
    Base.Threads.schedule(reconnect_task)
    errormonitor(reconnect_task)

    # TODO: refactor
    # 1. init socket
    # 2. run parser
    # 3. reconnect

    # connection_info = fetch(nc.info)
    # @info "Info: $connection_info."
    if default
        lock(state.lock) do; state.default_connection = nc end
    else
        lock(state.lock) do; push!(state.connections, nc) end
    end
    nc
end

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
# Cleanup subscription data when no more messages are expected.
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
