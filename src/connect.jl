
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

mutable struct State
    default_connection::Union{Connection, Nothing}
    connections::Vector{Connection}
    handlers::Dict{String, Function}
    "Handlers of messages for which handler was not found."
    fallback_handlers::Vector{Function}
    lock::ReentrantLock
    stats::Stats
end


function default_fallback_handler(::Connection, msg::Union{Msg, HMsg})
    @warn "Unexpected message delivered." msg
end

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
        @debug "Sening $message but connection status is $st."
    end
    while !isopen(nc.outbox) # TODO: this check is not threadsafe, use try catch.
        sleep(1)
    end
    put!(nc.outbox, message)
end

function sendloop(nc::Connection, io::IO)
    mime = MIME_PROTOCOL() 
    while true
        pending = Base.n_avail(nc.outbox)
        buf = IOBuffer()
        batch = pending

        for _ in 1:batch
            msg = take!(nc.outbox)
            if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                @lock state.lock begin nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
            end
            show(buf, mime, msg)
        end
        write(io, take!(buf))
    end
end

function socket_connect(port::Integer)
    Sockets.connect(port)
end

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(socket_connect, delays=SOCKET_CONNECT_DELAYS)(port)
    lock(state.lock) do; nc.status = CONNECTED end
    sender_task = Threads.@spawn :default disable_sigint() do; sendloop(nc, sock) end
    # TODO: better monitoring of sender with `bind`.
    # errormonitor(sender_task)
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
    sleep(3) # TODO: remove this sleep, use `retry` on `Sockets.connect`.
    if nc.status in [CLOSING, CLOSED, FAILURE]
        # @info "Connection is closing."
        error("Connection closed.")
    end
    @info "Disconnected. Trying to reconnect."
    new_outbox = Channel{ProtocolMessage}(OUTBOX_SIZE)
    put!(new_outbox, con_msg)
    # TODO: restore old subs.
    
    migrated = []
    for (sid, sub) in pairs(nc.subs)
        push!(migrated, sub)
        if haskey(nc.unsubs, sid)
            push!(migrated, Unsub(sid, nc.unsubs[sid]))
        end
    end
    @info "Migratting $(length(migrated)) subs to a new connection."
    for msg in migrated
        put!(new_outbox, msg)
    end
    for msg in collect(nc.outbox)
        if msg isa Msg || msg isa HMsg || msg isa Pub || msg isa HPub || msg isa Unsub
            put!(new_outbox, msg)
        end
    end
    lock(state.lock) do; nc.status = RECONNECTING end
    lock(state.lock) do; nc.outbox = new_outbox end
end

"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See [`Connect protocol message`](../protocol/#NATS.Connect).
"""
function connect(host::String = NATS_HOST, port::Int = NATS_PORT; default = true, kw...)
    if default && !isnothing(state.default_connection)
        return default_connection()
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
    nc.status = CLOSING
    close(nc.outbox)
    sleep(3)
    nc.status = CLOSED
    # TODO: set status DRAINING on connection 
    # stop all subs
    # wait all subs processed
    # wait all messages send
    # remove connection from CONNECTIONS
    # close connection
end

function drain()
    @info "Draining all connections."
    isnothing(state.default_connection) || drain(state.default_connection)
    drain.(state.connections)
    sleep(5) # simulate some work
    @info "All connections drained."
    nothing
end
