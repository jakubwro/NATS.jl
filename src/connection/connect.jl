
function validate_connect_options(server_info::Info, options)
    # TODO: maybe better to rely on server side validation. Grab Err messages and decide if conn should be terminated.
    server_info.proto > 0 || error("Server supports too old protocol version.")
    server_info.headers   || error("Server does not support headers.") # TODO: maybe this can be relaxed.

    # Check TLS requirements
    if get(options, :tls_required, false)
        !isnothing(server_info.tls_available) && server_info.tls_available || error("Client requires TLS but it is not available for the server.")
    end
end

function init_streams(host, port, options)
    sock = Sockets.connect(port) # TODO: retry logic.
    info_msg = next_protocol_message(sock)
    info_msg isa Info || error("Expected INFO, received $info_msg")
    @info "Server info" info_msg
    validate_connect_options(info_msg, options)
    # @show fetch(nc.info)
    read_stream, write_stream = sock, sock
    if !isnothing(info_msg.tls_required) && info_msg.tls_required
        (read_stream, write_stream) = upgrade_to_tls(sock)
        @info "Socket upgraded"
    end
    sock, read_stream, write_stream, info_msg
end


#TODO: restore link #NATS.Connect
"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See `Connect protocol message`.
"""
function connect(host::String = NATS_HOST, port::Int = NATS_PORT; default = true, cert_file = nothing, key_file = nothing, kw...)
    if default && !isnothing(state.default_connection)
        return default_connection() # report error instead
    end

    options = merge(DEFAULT_CONNECT_ARGS, kw)
    sock, read_stream, write_stream, info_msg = init_streams(host, port, options)
    connect_msg = from_kwargs(Connect, DEFAULT_CONNECT_ARGS, kw)

    nc = Connection(info_msg)
    # TODO: upgrade TLS here, to not catch timeout.
    spawn_sticky_task(() ->
        begin
            while true # TODO: While is drained.
                receiver_task = spawn_sticky_task(() -> while !eof(read_stream) process(nc, next_protocol_message(read_stream)) end)
                sender_task = spawn_sticky_task(() -> sendloop(nc, write_stream)) #TODO: while !eof

                err_channel = Channel()
                bind(err_channel, receiver_task)
                bind(err_channel, sender_task)

                send(nc, connect_msg)
                status(nc, CONNECTED)
                
                try
                    wait(err_channel)
                catch err
                    istaskfailed(receiver_task) && @error "Receiver task failed:" receiver_task.result
                    istaskfailed(sender_task) && @error "Sender task failed:" sender_task.result
                    close(nc.outbox)
                    close(sock)
                end
                try wait(sender_task) catch end
                try wait(receiver_task) catch end
                @info "Disconnected. Trying to reconnect."
                status(nc, RECONNECTING)

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
                lock(state.lock) do; nc.outbox = new_outbox end
                
                @info "Trying to connect nats://$host:$port"
                start_time = time()
                sock, read_stream, write_stream, info_msg = retry(init_streams, delays=SOCKET_CONNECT_DELAYS)(host, port, options)
                info(nc, info_msg)
                @info "Connected after $(time() - start_time) s."
            end
        end)

    if default
        lock(state.lock) do; state.default_connection = nc end
    else
        lock(state.lock) do; push!(state.connections, nc) end
    end
    nc
end
