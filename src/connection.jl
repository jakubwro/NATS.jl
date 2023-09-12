struct Connection
    io::IO
    info::Channel{Info}
    subs::Dict{String, Channel}
    unsubs::Dict{String, Int64}
    outbox::Channel{ProtocolMessage}
    lock::ReentrantLock
end

show(io::IO, connection::Connection) = print(io, typeof(connection), "(",
    connection.io, ", " , length(connection.subs)," subs, ", connection.outbox.n_avail_items ," msgs in outbox)")

function send(conn::Connection, message::ProtocolMessage)
    put!(conn.outbox, message)
end

function connect(
    host = NATS_DEFAULT_HOST,
    port = NATS_DEFAULT_PORT;
    verbose::Bool = true,
    pedantic::Bool = true,
    tls_required::Bool = false,
    auth_token::Union{String, Nothing} = nothing,
    user::Union{String, Nothing} = nothing,
    pass::Union{String, Nothing} = nothing,
    name::Union{String, Nothing} = nothing,
    lang::String = NATS_CLIENT_LANG,
    version::String = NATS_CLIENT_VERSION,
    protocol::Union{Int, Nothing} = nothing,
    echo::Union{Bool, Nothing} = nothing,
    sig::Union{String, Nothing} = nothing,
    jwt::Union{String, Nothing} = nothing,
    no_responders::Union{Bool, Nothing} = nothing,
    headers::Union{Bool, Nothing} = nothing,
    nkey::Union{String, Nothing} = nothing
)
    @debug "Connecting to nats://$host:$port."
    sock = Sockets.connect(port)
    @debug "Connected to nats://$host:$port."
    connection = Connection(sock, Channel{Info}(10), Dict{String, Channel}(), Dict{String, Int64}(), Channel{ProtocolMessage}(100), ReentrantLock())
    @debug "Starting listeners."
    @async process_server_messages(connection)
    @async process_client_messages(connection)
    @debug "Waiting for server INFO."
    # connection_info = fetch(connection.info)
    # @debug "Info: $connection_info."
    @debug "Sending CONNECT."
    send(connection, Connect(verbose, pedantic, tls_required, auth_token, user, pass, name, lang, version, protocol, echo, sig, jwt, no_responders, headers, nkey))
    connection
end

function close(conn::Connection)
    lock(conn.lock) do
        for (sid, ch) in conn.subs
            Sockets.close(ch)
        end
        empty!(conn.subs)
    end
    
    close(conn.io)
end

function ping(conn)
    send(conn, Ping())
end

"""
Cleanup subscription data when no more messages are expected.
This method is NOT threadsafe.
"""
function _cleanup_sub(conn::Connection, sid::String)
    if haskey(conn.subs, sid)
        close(conn.subs[sid])
        delete!(conn.subs, sid)
    end
    delete!(conn.unsubs, sid)
end

function connection_init(host = "localhost", port = 4222)
    sock = Sockets.connect(host, port)
    info = next_protocol_message(sock)
    info isa Info || error("Expected INFO message, received $msg.")
    sock, info
end

function theloop()
    while true
        io, info = connection_init()
        # send connect
        # send existing subs
        # start processor 
    end
end

function process_server_messages(conn)
    while true
        try
            process(conn, @show next_protocol_message(conn.io))
        catch e
            @show e
            @warn "Error parsing protocol message. Closing connection."
            close(conn)
            break
        end
    end
end

function process_client_messages(conn)
    while true
        try
            msg = take!(conn.outbox)
            if msg isa Unsub && !isnothing(msg.max_msgs)
                @warn "Unsub"
                conn.unsubs[msg.sid] = msg.max_msgs
            end
            write(conn.io, serialize(msg))
        catch e
            @show e
            break
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

function process(conn::Connection, ping::Ping)
    @debug "Sending PONG."
    write(conn.io, serialize(Pong())) # Reply immediately bypassing outbox channel.
end

function process(conn::Connection, pong::Pong)
    @debug "Received pong."
end

function process(conn::Connection, msg::Msg)
    @debug "Received Msg."
    ch = lock(conn.lock) do
        get(conn.subs, msg.sid, nothing)
    end
    if isnothing(ch)
        @error "No subscription found for sid $(msg.sid)"
    elseif !isopen(ch)
        @warn "Subscription channel is closed. Dropping off message."
    else
        put!(ch, msg)
        lock(conn.lock) do
            count = get(conn.unsubs, msg.sid, nothing)
            if !isnothing(count)
                count = count - 1
                if count == 0
                    _cleanup_sub(conn, msg.sid)
                else
                    conn.unsubs[msg.sid] = count
                end
            end
        end
    end
end

function process(conn::Connection, hmsg::HMsg)
    @debug "Received HMsg."
end

function process(conn::Connection, ok::Ok)
    @debug "Received OK."
end

function process(conn::Connection, err::Err)
    @debug "Received Err."
    @show err
end
