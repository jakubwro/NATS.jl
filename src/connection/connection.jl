
include("structs.jl")
include("utils.jl")
include("tls.jl")
include("send.jl")
include("handlers.jl")

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
function socket_connect(port::Integer)
    Sockets.connect(port)
end

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(socket_connect, delays=SOCKET_CONNECT_DELAYS)(port)
    
    read_stream = sock
    write_stream = sock

    process(nc, next_protocol_message(read_stream))
    info = fetch(nc.info)
    send(nc, con_msg)
    
    # @show fetch(nc.info)
    if !isnothing(info.tls_required) && info.tls_required
        (read_stream, write_stream) = upgrade_to_tls(sock)
        @info "Socket upgraded"
    end

    lock(state.lock) do; nc.status = CONNECTED end

    receiver_task = Threads.Task(() -> begin
        while true
            process(nc, next_protocol_message(read_stream))
        end
    end)
    Base.Threads._spawn_set_thrpool(receiver_task, :default)
    Base.Threads.schedule(receiver_task)
    errormonitor(receiver_task)

    sender_task = Threads.@spawn :default disable_sigint() do; sendloop(nc, write_stream) end
    # TODO: better monitoring of sender with `bind`.
    errormonitor(sender_task)
    try
        wait(receiver_task)
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
    # if nc.status in [CLOSING, CLOSED, FAILURE]
        # @info "Connection is closing."
        # error("Connection closed.")
    # end
    @info "Disconnected. Trying to reconnect."
    new_outbox = Channel{ProtocolMessage}(OUTBOX_SIZE)
    # TODO: restore old subs.
    
    migrated = []
    for (sid, sub) in pairs(nc.subs)
        push!(migrated, sub)
        if haskey(nc.unsubs, sid)
            push!(migrated, Unsub(sid, nc.unsubs[sid]))
        end
    end
    @info "Migrating $(length(migrated)) subs to a new connection."
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
    reconnect_task = Base.Threads.Task(() ->  disable_sigint() do; while true reconnect(nc, host, port, connect_msg) end end)
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
