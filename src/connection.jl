struct Connection
    io::IO
    info::Channel{Info}
    subs::Dict{String, Channel}
    outbox::Channel{ProtocolMessage}
    tasks::Vector{Task}
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
    connection = Connection(sock, Channel{Info}(10), Dict{String, Channel}(), Channel{ProtocolMessage}(100), Task[], ReentrantLock())
    @debug "Starting listeners."
    start!(connection)
    @debug "Waiting for server INFO."
    connection_info = fetch(connection.info)
    @debug "Info: $connection_info."
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

function publish(conn::Connection, subject::String; reply_to::Union{String, Nothing} = nothing, payload::Union{String, Nothing} = nothing, headers::Union{Nothing, Dict{String, Vector{String}}} = nothing)
    if isnothing(headers)
        nbytes = isnothing(payload) ? 0 : ncodeunits(payload)
        send(conn, Pub(subject, reply_to, nbytes, payload))
    else
        
    end
end

function subscribe(f, conn::Connection, subject::String; queue_group::Union{String, Nothing} = nothing, sync = true)
    sid = randstring()
    SUBSCRIPTION_CHANNEL_SIZE = 10
    ch = Channel(SUBSCRIPTION_CHANNEL_SIZE)
    lock(conn.lock) do
        conn.subs[sid] = ch
    end
    t = Threads.@spawn :default begin
        while true
            try
                msg = take!(ch)
                task = Threads.@spawn :default try
                    res = f(msg)
                    if !isnothing(msg.reply_to)
                        publish(conn, msg.reply_to, res)
                    end
                catch e
                    @error e
                end
                sync && wait(task)
            catch e
                if e isa InvalidStateException
                    # Closed channel, stop.
                else
                    @error e
                end
                break
            end
        end
    end

    sub = Sub(subject, queue_group, sid)
    send(conn, sub)
    sub
end

function unsubscribe(conn::Connection, sub::Sub; max_msgs::Union{Int, Nothing} = nothing)
    sid = sub.sid
    send(conn, Unsub(sid, max_msgs))
    lock(conn.lock) do
        close(conn.subs[sid])
        delete!(conn.subs, sid)
    end
    nothing
end

function start!(conn::Connection)
    receiver = Threads.@spawn :interactive begin
        while true
            try
                if !isopen(conn.io)
                    @warn "EOF"
                    break
                end
                process(conn, next_protocol_message(conn.io))
            catch e
                @show e
                @warn "Error parsing protocol message. Closing connection."
                close(conn)
            end
        end
    end
    
    sender = Threads.@spawn :interactive begin
        while true
            try
                if !isopen(conn.io)
                    @warn "EOF"
                    break
                end
                msg = take!(conn.outbox)
                write(conn.io, serialize(msg))
                @show isopen(conn.io)
            catch e
                @show e
            end
        end
    end

    push!(conn.tasks, receiver)
    push!(conn.tasks, sender)
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
    else
        put!(ch, msg)
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
end
