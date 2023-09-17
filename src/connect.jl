
@enum ConnectionStatus CONNECTING CONNECTED RECONNECTING CLOSING CLOSED FAILURE

mutable struct Connection
    status::ConnectionStatus
    info::Channel{Info}
    unsubs::Dict{String, Int64}
    handlers::Dict{String, Function}
    outbox::Channel{ProtocolMessage}
    lock::ReentrantLock
    function Connection()
        new(CONNECTING, Channel{Info}(10), Dict{String, Channel}(), Dict{String, Int64}(), Channel{ProtocolMessage}(OUTBOX_SIZE), ReentrantLock())
    end
end

info(nc::Connection) = fetch(nc.info)
status(nc::Connection) = @lock nc.lock nc.status
outbox(nc::Connection) = @lock nc.lock nc.outbox

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    status(nc), ", " , length(nc.handlers)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

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
            @lock nc.lock nc.unsubs[msg.sid] = msg.max_msgs # TODO: move it somewhere else
        end
        show(io, MIME("application/nats"), msg)
        take!(nc.outbox)
    end
end

@mockable function mockable_socket_connect(port::Integer)
    # @show Pretend.activated()
    Pretend.activated() && @warn "Using mocked connection."
    Sockets.connect(port)
end

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(mockable_socket_connect, delays=SOCKET_CONNECT_DELAYS)(port)
    lock(nc.lock) do; nc.status = CONNECTED end
    sender_task = Threads.@spawn :default disable_sigint() do; sendloop(nc, sock) end
    try
        while true
            process(nc, next_protocol_message(sock))
        end
    catch err
        @error err
        close(nc.outbox)
        close(sock)
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
    lock(nc.lock) do; nc.status = RECONNECTING end
    lock(nc.lock) do; nc.outbox = new_outbox end
end

"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See [`Connect protocol message`](../protocol/#NATS.Connect).
"""
function connect(host::String = NATS_DEFAULT_HOST, port::Int = NATS_DEFAULT_PORT; kw...)
    nc = Connection()
    con_msg = Connect(merge(DEFAULT_CONNECT_ARGS, kw)...)
    send(nc, con_msg)
    reconnect_task = Threads.@spawn :default disable_sigint() do; while true reconnect(nc, host, port, con_msg) end end
    errormonitor(reconnect_task)

    # TODO: refactor
    # 1. init socket
    # 2. run parser
    # 3. reconnect

    # connection_info = fetch(nc.info)
    # @info "Info: $connection_info."
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
    lock(nc.lock) do; nc.status = CLOSING end
    lock(nc.lock) do
        for (sid, _) in nc.handlers
            unsubscribe(nc, sid)
        end
    end
    try close(nc.outbox) catch end
    lock(nc.lock) do; nc.status = CLOSED end
end

function ping(nc)
    send(nc, Ping())
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_sub(nc::Connection, sid::String)
    lock(nc.lock) do
        delete!(nc.handlers, sid)
        delete!(nc.unsubs, sid)
    end
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_unsub_msg(nc::Connection, sid::String)
    lock(nc.lock) do
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
    handler = lock(nc.lock) do
        get(nc.handlers, msg.sid, nothing)
    end
    if isnothing(handler)
        needs_ack(msg) && nak(nc, msg)
    else
        handler_task = Threads.@spawn :default begin
            T = methods(handler)[1].sig.parameters[2]
            Base.invokelatest(handler, convert(T, msg))
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
