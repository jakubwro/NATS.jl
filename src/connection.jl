
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

function send(nc::Connection, message::ProtocolMessage)
    if status(nc::Connection) in [CLOSED, FAILURE]
        error("Connection is broken.")
    end
    put!(nc.outbox, message)
end

function sendloop(nc::Connection, io::IO)
    while true
        msg = fetch(nc.outbox)
        if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
            @lock nc.lock nc.unsubs[msg.sid] = msg.max_msgs # TODO: move it somewhere else
        end
        write(io, serialize(msg))
        take!(nc.outbox)
    end
end

function parserloop(nc::Connection, io::IO)
    while true
        process(nc, next_protocol_message(io))
    end
end

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(Sockets.connect, delays=Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1))(port)
    lock(nc.lock) do; nc.status = CONNECTED end
    ch = Channel(0)
    sender_task = Threads.@spawn :default disable_sigint() do; sendloop(nc, sock) end
    parser_task = Threads.@spawn :default disable_sigint() do; parserloop(nc, sock) end
    bind(ch, sender_task)
    bind(ch, parser_task)
    try take!(ch) catch err end
    close(sock)
    close(nc.outbox)
    try wait(sender_task) catch err @debug "Sender task finished." err end
    try wait(parser_task) catch err @debug "Parser task finished." err end
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

function connect(host::String = NATS_DEFAULT_HOST, port::Int = NATS_DEFAULT_PORT; kw...)
    nc = Connection()
    con_msg = Connect(merge(DEFAULT_CONNECT_ARGS, kw)...)
    send(nc, con_msg)
    reconnect_task = Threads.@spawn :default disable_sigint() do; while true reconnect(nc, host, port, con_msg) end end
    errormonitor(reconnect_task)

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

function close(conn::Connection)
    lock(conn.lock) do; conn.status = CLOSING end
    lock(conn.lock) do
        for (sid, f) in conn.handlers
            unsubscribe(conn, sid)
        end
    end
    try close(conn.outbox) catch end
    lock(conn.lock) do; conn.status = CLOSED end
end

function ping(conn)
    send(conn, Ping())
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_sub(conn::Connection, sid::String)
    lock(conn.lock) do
        delete!(conn.handlers, sid)
        delete!(conn.unsubs, sid)
    end
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_unsub_msg(conn::Connection, sid::String)
    lock(conn.lock) do
        count = get(conn.unsubs, sid, nothing)
        if !isnothing(count)
            count = count - 1
            if count == 0
                _cleanup_sub(conn, sid)
            else
                conn.unsubs[sid] = count
            end
        end
    end
end

function process(conn::Connection, msg::ProtocolMessage)
    @error "Unexpected protocol message $msg."
end

function process(conn::Connection, info::Info)
    @debug "New INFO received."
    put!(conn.info, info)
    while conn.info.n_avail_items > 1
        @debug "Dropping old info"
        take!(conn.info)
    end
end

function process(nc::Connection, ping::Ping)
    @debug "Sending PONG."
    send(nc, Pong())
end

function process(conn::Connection, pong::Pong)
    @debug "Received pong."
end

function process(conn::Connection, msg::Msg)
    @debug "Received $msg"
    f = lock(conn.lock) do
        get(conn.handlers, msg.sid, nothing)
    end
    
    t = Threads.@spawn :default Base.invokelatest(f, msg)
    errormonitor(t)
    # Base.invokelatest(f, msg)
    _cleanup_unsub_msg(conn, msg.sid)
end

function process(nc::Connection, hmsg::HMsg)
    @debug "Received HMsg."
end

function process(nc::Connection, ok::Ok)
    @debug "Received OK."
end

function process(nc::Connection, err::Err)
    @debug "Received Err."
    @show err
end
