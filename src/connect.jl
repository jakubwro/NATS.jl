
@enum ConnectionStatus CONNECTING CONNECTED RECONNECTING CLOSING CLOSED FAILURE


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

struct State
    connections::Vector{Connection}
    handlers::Dict{String, Function}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
end


function default_fallback_handler(::Connection, msg::Union{Msg, HMsg})
    @error "Unexpected message delivered." msg
end

const state = State(Connection[], Dict{String, Function}(), Function[default_fallback_handler], ReentrantLock(), Stats(0, 0))

function status()
    println("=== Connection status ====================")
    println("connections:    $(length(state.connections))        ")
    for (i, nc) in enumerate(state.connections)
        print("  [#$i]:  ")
        print(status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox             ")
        println()
    end
    println("subscriptions:  $(length(state.handlers))           ")
    println("msgs_handled:   $(state.stats.msgs_handled)         ")
    println("msgs_unhandled: $(state.stats.msgs_not_handled)        ")
    println("==========================================")
end

function istatus(cond = nothing)
    try
        while true
            status()
            sleep(0.05)
            if !isnothing(cond) && !isopen(cond)
                return
            end
            write(stdout, "\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K")
        end
    catch e
        if !(e isa InterruptException)
            throw(e)
        end
    end
end

function default_connection()
    if isempty(state.connections)
        error("No connection availabe. Call `NATS.connect()` before.")
    end

    # TODO: This is temporary workaround, find better way to handle multiple connections.
    last(state.connections)
end

info(nc::Connection) = fetch(nc.info)
status(nc::Connection) = @lock state.lock nc.status
outbox(nc::Connection) = @lock state.lock nc.outbox

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

"""
Enqueue protocol message in `outbox` to be written to socket.
"""
function send(nc::Connection, message::ProtocolMessage)
    st = status(nc::Connection)
    if st in [CLOSED, FAILURE]
        error("Connection is broken.")
    elseif st != CONNECTED && st != CONNECTING
        @warn "Connection status: $st"
    end
    put!(nc.outbox, message)
end

function sendloop(nc::Connection, io::IO)
    while true
        msg = fetch(nc.outbox)
        if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
            lock(state.lock) do; nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
        end
        show(io, MIME_PROTOCOL(), msg)
        take!(nc.outbox)
    end
end

@mockable function mockable_socket_connect(port::Integer)
    Pretend.activated() && @warn "Using mocked connection."
    Sockets.connect(port)
end

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(mockable_socket_connect, delays=SOCKET_CONNECT_DELAYS)(port)
    lock(state.lock) do; nc.status = CONNECTED end
    sender_task = Threads.@spawn :default disable_sigint() do; sendloop(nc, sock) end
    errormonitor(sender_task)
    try
        while true
            process(nc, next_protocol_message(sock))
        end
    catch err
        @error err
        close(nc.outbox)
        close(sock)
        # TODO: distinguish recoverable and unrecoverable exceptions.
        # throw(err)
    end
    try
        wait(sender_task)
    catch err
        @debug "Sender task finished." err
    end
    if nc.status in [CLOSING, CLOSED, FAILURE]
        # @info "Connection is closing."
        error("Connection closed.")
    end
    @info "Disconnected. Trying to reconnect."
    new_outbox = Channel{ProtocolMessage}(OUTBOX_SIZE)
    put!(new_outbox, con_msg)
    # TODO: restore old subs.
    for msg in collect(nc.outbox)
        # TODO: skip Connect, Ping, Pong
        put!(new_outbox, msg)
    end
    lock(state.lock) do; nc.status = RECONNECTING end
    lock(state.lock) do; nc.outbox = new_outbox end
end

"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See [`Connect protocol message`](../protocol/#NATS.Connect).
"""
function connect(host::String = NATS_DEFAULT_HOST, port::Int = NATS_DEFAULT_PORT; kw...)
    if !isempty(state.connections)
        return first(state.connections)
    end
    nc = Connection()
    connect_msg = from_kwargs(Connect, DEFAULT_CONNECT_ARGS, kw)
    send(nc, connect_msg)
    reconnect_task = Threads.@spawn :default disable_sigint() do; while true reconnect(nc, host, port, connect_msg) end end
    errormonitor(reconnect_task)

    # TODO: refactor
    # 1. init socket
    # 2. run parser
    # 3. reconnect

    # connection_info = fetch(nc.info)
    # @info "Info: $connection_info."
    lock(state.lock) do; push!(state.connections, nc) end
    nc
end

function connect(x, host::String = NATS_DEFAULT_HOST, port::Int = NATS_DEFAULT_PORT; kw...)
    nc = connect(host, port; kw...)
    try
        x(nc)
    finally
        close(nc)
    end
end

function close(nc::Connection)
    lock(state.lock) do; nc.status = CLOSING end
    lock(state.lock) do
        for (sid, sub) in nc.subs
            unsubscribe(nc, sub)
        end
    end
    try close(nc.outbox) catch end
    lock(state.lock) do; nc.status = CLOSED end
end

function ping(nc)
    send(nc, Ping())
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_sub(nc::Connection, sid::String)
    lock(state.lock) do
        delete!(state.handlers, sid)
        delete!(nc.subs, sid)
        delete!(nc.unsubs, sid)
    end
end

"""
Cleanup subscription data when no more messages are expected.
"""
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

function process(nc::Connection, msg::ProtocolMessage)
    @error "Unexpected protocol message $msg."
end

function process(nc::Connection, info::Info)
    @debug "New INFO received."
    put!(nc.info, info)
    while nc.info.n_avail_items > 1
        @debug "Dropping old info"
        take!(nc.info)
    end
end

function process(nc::Connection, ping::Ping)
    @debug "Sending PONG."
    send(nc, Pong())
end

function process(nc::Connection, pong::Pong)
    @info "Received pong."
end

function process(nc::Connection, msg::Union{Msg, HMsg})
    @debug "Received $msg"
    handler = lock(state.lock) do
        h = get(state.handlers, msg.sid, nothing)
        if !isnothing(h)
            nc.stats.msgs_handled = nc.stats.msgs_handled + 1
            state.stats.msgs_handled = state.stats.msgs_handled + 1
        end
        h
    end
    if isnothing(handler)
        fallbacks = lock(state.lock) do
            collect(state.fallback_handlers)
        end
        for f in fallbacks
            Base.invokelatest(f, nc, msg)
        end
        lock(state.lock) do
            nc.stats.msgs_not_handled = nc.stats.msgs_not_handled + 1
            state.stats.msgs_not_handled = state.stats.msgs_not_handled + 1
        end
    else
        handler_task = Threads.@spawn :default begin
            # lock(state.lock) do # TODO: rethink locking of handlers execution. Probably not very useful.
                T = argtype(handler)
                Base.invokelatest(handler, convert(T, msg))
            # end
        end
        errormonitor(handler_task) # TODO: find nicer way to debug handler failures.
        _cleanup_unsub_msg(nc, msg.sid)
    end
end

function process(nc::Connection, ok::Ok)
    @debug "Received OK."
end

function process(nc::Connection, err::Err)
    @error "NATS protocol error!" err
end

function drain(nc::Connection)
    # TODO: set status DRAINING on connection 
    # stop all subs
    # wait all subs processed
    # wait all messages send
    # remove connection from CONNECTIONS
    # close connection
end

function drain()
    drain.(CONNECTIONS)
    nothing
end
