# Stuff for gracefuly handling reconnects, especially restoring subscriptions.

function reconnect(nc::Connection, host, port, con_msg)
    sock = retry(Sockets.connect, delays=SOCKET_CONNECT_DELAYS)(port)
    
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
        while !eof(read_stream)
            process(nc, next_protocol_message(read_stream))
        end
    end)
    Base.Threads._spawn_set_thrpool(receiver_task, :default)
    Base.Threads.schedule(receiver_task)
    sender_task = Threads.Task(() -> sendloop(nc, write_stream))
    Base.Threads._spawn_set_thrpool(sender_task, :default)
    Base.Threads.schedule(sender_task)

    c = Channel()
    bind(c, receiver_task)
    bind(c, sender_task)
    try
        wait(c)
    catch err
        if istaskfailed(receiver_task)
            @error "Receiver task failed:" receiver_task.result
        end
        if istaskfailed(sender_task)
            @error "Sender task failed:" sender_task.result
        end

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
