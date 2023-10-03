# Stuff for gracefuly handling reconnects, especially restoring subscriptions.

function socket_reconnect(nc::Connection, host, port, con_msg)
    sock = Sockets.connect(port)
    info_msg = next_protocol_message(sock)
    info_msg isa Info || error("Expected INFO, received $info_msg")
    # process(nc, info_msg)
    @info "Server info" info_msg
    read_stream, write_stream = sock, sock
    if !isnothing(info_msg.tls_required) && info_msg.tls_required
        (read_stream, write_stream) = upgrade_to_tls(sock)
        @info "Socket upgraded"
    end
    sock, read_stream, write_stream
end

function reconnect(nc::Connection, host, port, con_msg; sock, read_stream, write_stream)
    if isnothing(sock) || !isopen(sock)
        @info "Trying to connect nats://$host:$port"
        start_time = time()
        sock, read_stream, write_stream = retry(socket_reconnect, delays=SOCKET_CONNECT_DELAYS)(nc::Connection, host, port, con_msg)
        @info "Connected after $(time() - start_time) s."
    end
    receiver_task = spawn_sticky_task(() -> begin
        while !eof(read_stream)
            process(nc, next_protocol_message(read_stream))
        end
    end)
    sender_task = spawn_sticky_task(() -> sendloop(nc, write_stream))
    c = Channel()
    bind(c, receiver_task)
    bind(c, sender_task)
    send(nc, con_msg)
    status(nc, CONNECTED)
    try
        wait(c)
    catch err
        istaskfailed(receiver_task) && @error "Receiver task failed:" receiver_task.result
        istaskfailed(sender_task) && @error "Sender task failed:" sender_task.result
        close(nc.outbox)
        close(sock)
    end
    try wait(sender_task) catch end
    try wait(receiver_task) catch end
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
