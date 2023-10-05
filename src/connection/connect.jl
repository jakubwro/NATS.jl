
function validate_connect_options(server_info::Info, options)
    # TODO: maybe better to rely on server side validation. Grab Err messages and decide if conn should be terminated.
    server_info.proto > 0 || error("Server supports too old protocol version.")
    server_info.headers   || error("Server does not support headers.") # TODO: maybe this can be relaxed.

    # Check TLS requirements
    if get(options, :tls_required, false)
        !isnothing(server_info.tls_available) && server_info.tls_available || error("Client requires TLS but it is not available for the server.")
    end
end

function init_protocol(host, port, nkey_seed, options)
    sock = Sockets.connect(port)
    try
        info_msg = next_protocol_message(sock)
        info_msg isa Info || error("Expected INFO, received $info_msg")
        validate_connect_options(info_msg, options)
        read_stream, write_stream = sock, sock
        if !isnothing(info_msg.tls_required) && info_msg.tls_required
            (read_stream, write_stream) = upgrade_to_tls(sock)
            @info "Socket upgraded"
        end

        if !isnothing(info_msg.nonce)
            isnothing(nkey_seed) && error("Server requires signature but no `nkey_seed` provided.")
            isnothing(options.nkey) && error("Missing `nkey` parameter.")
            sig = sign(info_msg.nonce, nkey_seed)
            options = merge(options, (sig = sig,))
        end

        # TODO: sign nonce here.
        connect_msg = from_kwargs(Connect, DEFAULT_CONNECT_OPTIONS, options)
        show(write_stream, MIME_PROTOCOL(), connect_msg)
        flush(write_stream)

        show(write_stream, MIME_PROTOCOL(), Ping())
        flush(write_stream)

        msg = next_protocol_message(read_stream)
        msg isa Union{Ok, Err, Pong} || error("Expected +OK, -ERR or PONG , received $msg")
        if msg isa Err
            error(msg.message)
        elseif msg isa Ok
            # Client opted for a verbose connection, consume PONG to not mess logs.
            next_protocol_message(read_stream) isa Pong || error("Expected PONG, received $msg")
        end

        sock, read_stream, write_stream, info_msg
    catch
        close(sock)
        rethrow()
    end
end

function reopen_outbox(nc::Connection)
    new_outbox = Channel{ProtocolMessage}(OUTBOX_SIZE)
    for (sid, sub) in pairs(nc.subs)
        put!(new_outbox, sub)
        if haskey(nc.unsubs, sid)
            put!(new_outbox, Unsub(sid, nc.unsubs[sid]))
        end
    end
    subs_count = Base.n_avail(new_outbox)
    for msg in collect(nc.outbox)
        if msg isa Msg || msg isa HMsg || msg isa Pub || msg isa HPub || msg isa Unsub
            put!(new_outbox, msg)
        end
    end
    @info "New outbox have $(Base.n_avail(new_outbox)) protocol messages including $subs_count restored subs/unsubs."

    outbox(nc, new_outbox)
end

#TODO: restore link #NATS.Connect
"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See `Connect protocol message`.
"""
function connect(
    host::String = NATS_HOST,
    port::Int = NATS_PORT;
    default = true,
    nkey_seed = NATS_NKEY_SEED,
    tls_cert_file = nothing,
    tls_key_file = nothing,
    options...
)
    @info "Connecting to nats://$host:$port"
    if default && !isnothing(state.default_connection)
        return connection(:default) # TODO: report error instead
    end

    options = merge(DEFAULT_CONNECT_OPTIONS, options)
    sock, read_stream, write_stream, info_msg = init_protocol(host, port, nkey_seed, options)

    nc = Connection(info_msg)
    status(nc, CONNECTED)
    # TODO: task monitoring, warn about broken connection after n reconnects.
    spawn_sticky_task(() ->
        begin
            while true # TODO: While is drained.
                receiver_task = spawn_sticky_task(() -> while !eof(read_stream) process(nc, next_protocol_message(read_stream)) end)
                sender_task = spawn_sticky_task(() -> sendloop(nc, write_stream))

                err_channel = Channel()
                bind(err_channel, receiver_task)
                bind(err_channel, sender_task)
                
                try
                    wait(err_channel)
                catch err
                    istaskfailed(receiver_task) && @error "Receiver task failed:" receiver_task.result
                    istaskfailed(sender_task) && @error "Sender task failed:" sender_task.result
                    close(nc.outbox)
                    close(sock)
                end
                if isdrained(nc)
                    @warn "Drained, no reconnect."
                    break
                end
                try wait(sender_task) catch end
                reopen_outbox(nc) # Reopen outbox immediately old sender stops to prevent `send` blocking too long.
                try wait(receiver_task) catch end

                @warn "Reconnecting..."
                status(nc, CONNECTING)
                start_time = time()
                # TODO: handle repeating server Err messages.
                sock, read_stream, write_stream, info_msg = retry(init_protocol, delays=SOCKET_CONNECT_DELAYS)(host, port, nkey_seed, options)
                info(nc, info_msg)
                status(nc, CONNECTED)
                @lock nc.lock nc.stats.reconnections = nc.stats.reconnections + 1
                @lock state.lock state.stats.reconnections = state.stats.reconnections + 1
                @info "Reconnected after $(time() - start_time) s."
            end
        end)

    if default
        connection(:default, nc)
    end
    @lock state.lock push!(state.connections, nc)
    nc
end
