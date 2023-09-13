
@enum ConnectionStatus CONNECTING CONNECTED RECONNECTING CLOSED FAILURE

mutable struct Connection
    status::ConnectionStatus
    info::Channel{Info}
    subs::Dict{String, Channel}
    unsubs::Dict{String, Int64}
    outbox::Channel{ProtocolMessage}
    lock::ReentrantLock
    function Connection()
        new(CONNECTING, Channel{Info}(10), Dict{String, Channel}(), Dict{String, Int64}(), Channel{ProtocolMessage}(100), ReentrantLock())
    end
end

info(nc::Connection) = fetch(nc.info)
status(nc::Connection) = @lock nc.lock nc.status
outbox(nc::Connection) = @lock nc.lock nc.outbox

show(io::IO, nc::Connection) = print(io, typeof(nc), "(",
    status(nc), ", " , length(nc.subs)," subs, ", length(nc.unsubs)," unsubs, ", Base.n_avail(outbox(nc::Connection)) ," outbox)")

function send(nc::Connection, message::ProtocolMessage)
    if status(nc::Connection) in [CLOSED, FAILURE]
        error("Connection is broken.")
    end
    put!(nc.outbox, message)
end

function sendloop(nc::Connection, io::IO)
    try
        while true
            msg = fetch(nc.outbox)
            if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                @lock nc.lock nc.unsubs[msg.sid] = msg.max_msgs # TODO: move it somewhere else
            end
            write(io, serialize(msg))
            take!(nc.outbox)
        end
    catch e
        e
    end
end

function parserloop(nc::Connection, io::IO)
    try
        while true
            process(nc, next_protocol_message(io))
        end
    catch e
        e
    end
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
    nc = Connection()
    con_msg = Connect(verbose, pedantic, tls_required, auth_token, user, pass, name, lang, version, protocol, echo, sig, jwt, no_responders, headers, nkey)
    send(nc, con_msg)

    t = Threads.@spawn :interactive begin
        while true
            # delays = Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1)
            sock = retry(Sockets.connect, delays=Base.ExponentialBackOff(n=1000, first_delay=0.5, max_delay=1))(port)
            lock(nc.lock) do; nc.status = CONNECTED end
            sender_task = Threads.@spawn :interactive sendloop(nc, sock)
            parser_task = Threads.@spawn :interactive parserloop(nc, sock)
            wait(parser_task)
            @info "Disconnected. Trying to reconnect."
            close(nc.outbox)
            new_outbox = Channel{ProtocolMessage}(1000)
            put!(new_outbox, con_msg)
            # TODO: restore old subs.
            for msg in collect(nc.outbox)
                put!(new_outbox, msg)
            end
            lock(nc.lock) do; nc.status = RECONNECTING end
            wait(sender_task)
            lock(nc.lock) do; nc.outbox = new_outbox end
        end
    end
    errormonitor(t)

    # connection_info = fetch(nc.info)
    # @info "Info: $connection_info."
    nc
end

# function close(conn::Connection)
#     lock(conn.lock) do
#         for (sid, ch) in conn.subs
#             Sockets.close(ch)
#         end
#         empty!(conn.subs)
#     end
    
#     close(conn.io)
# end

function ping(conn)
    send(conn, Ping())
end

"""
Cleanup subscription data when no more messages are expected.
"""
function _cleanup_sub(conn::Connection, sid::String)
    # lock(conn.lock) do
        if haskey(conn.subs, sid)
            close(conn.subs[sid])
            delete!(conn.subs, sid)
        end
        # @show "deleting $sid"
        # sleep(0.1)
        delete!(conn.unsubs, sid)
    # end
end

function connection_init(host = "localhost", port = 4222)
    sock = Sockets.connect(host, port)
    info = next_protocol_message(sock)
    info isa Info || error("Expected INFO message, received $msg.")
    sock, info
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
    @debug "Received Msg."
    ch = lock(conn.lock) do
        get(conn.subs, msg.sid, nothing)
    end
    if isnothing(ch) || !isopen(ch)
        @warn "Noone awaits message for sid $(msg.sid)."
        needs_ack(msg) && nak(conn, msg)
    else
        put!(ch, msg) # TODO: catch exception and send NAK
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
