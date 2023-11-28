function default_connect_options()
    (
        # Options that are defined in the protocol, see Connect struct.
        verbose= parse(Bool, get(ENV, "NATS_VERBOSE", "false")),
        pedantic = parse(Bool, get(ENV, "NATS_PEDANTIC", "false")),
        tls_required = parse(Bool, get(ENV, "NATS_TLS_REQUIRED", "false")),
        auth_token = get(ENV, "NATS_AUTH_TOKEN", nothing),
        user = get(ENV, "NATS_USER", nothing),
        pass = get(ENV, "NATS_PASS", nothing),
        name = nothing,
        lang = NATS_CLIENT_LANG,
        version = NATS_CLIENT_VERSION,
        protocol = 1,
        echo = nothing,
        sig = nothing,
        jwt = get(ENV, "NATS_JWT", nothing),
        no_responders = true,
        headers = true,
        nkey = get(ENV, "NATS_NKEY", nothing),
        # Options used only on client side, never sent to server.
        nkey_seed = get(ENV, "NATS_NKEY_SEED", nothing),
        tls_ca_cert_path = get(ENV, "NATS_CA_CERT_PATH", "test/certs/nats.crt"), # TODO: remove this hardcoded paths
        tls_client_cert_path = get(ENV, "NATS_CLIENT_CERT_PATH", "test/certs/client.crt"),
        tls_client_key_path = get(ENV, "NATS_CLIENT_KEY_PATH", "test/certs/client.key")
    )
end

function validate_connect_options(server_info::Info, options)
    # TODO: check if proto is 1 when `echo` flag is set

    # TODO: maybe better to rely on server side validation. Grab Err messages and decide if conn should be terminated.
    server_info.proto > 0 || error("Server supports too old protocol version.")
    server_info.headers   || error("Server does not support headers.") # TODO: maybe this can be relaxed.

    # Check TLS requirements
    if get(options, :tls_required, false)
        !isnothing(server_info.tls_available) && server_info.tls_available || error("Client requires TLS but it is not available for the server.")
    end
end

function connect_urls(nc::Connection)::Vector{Tuple{String, Int}}
    urls = info(nc).connect_urls
    if isnothing(urls)
        [(nc.host, nc.port)]
    else
        map(urls) do url
            @assert ':' in url "$url is not correct"
            host, port = split(url, ":")
            host, parse(Int, port)
        end
    end
end

function init_protocol(host, port, options; nc = nothing)
    if !isnothing(nc)
        # If this is an existing connection, try to use other cluster server.
        host, port = rand(connect_urls(nc))
    end
    sock = Sockets.connect(host, port)
    try
        info_msg = next_protocol_message(sock)
        info_msg isa Info || error("Expected INFO, received $info_msg")
        validate_connect_options(info_msg, options)
        read_stream, write_stream = sock, sock
        if !isnothing(info_msg.tls_required) && info_msg.tls_required
            tls_options = options[(:tls_ca_cert_path, :tls_client_cert_path, :tls_client_key_path)]
            (read_stream, write_stream) = upgrade_to_tls(sock, tls_options...)
            @info "Socket upgraded"
        end

        if !isnothing(info_msg.nonce)
            isnothing(options.nkey_seed) && error("Server requires signature but no `nkey_seed` provided.")
            isnothing(options.nkey) && error("Missing `nkey` parameter.")
            sig = sign(info_msg.nonce, options.nkey_seed)
            options = merge(options, (sig = sig,))
        end

        defaults = default_connect_options()
        known_options = keys(defaults)
        provided_keys = keys(options)
        keys_df = setdiff(provided_keys, known_options)
        !isempty(keys_df) && error("Unknown `connect` options: $(join(keys_df, ", "))") 
        connect_msg = from_options(Connect, options)
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

        if !isnothing(nc)
            nc.host, nc.port = host, port
        end
        sock, read_stream, write_stream, info_msg
    catch err
        close(sock)
        rethrow()
    end
end

function reopen_outbox(nc::Connection)
    old_outbox = outbox(nc)
    new_outbox = Channel{ProtocolMessage}(old_outbox.sz_max)
    # sids = Set{String}()
    # for (sid, sub) in pairs(nc.subs)
    #     put!(new_outbox, sub)
    #     push!(sids, sid)
    #     if haskey(nc.unsubs, sid)
    #         put!(new_outbox, Unsub(sid, nc.unsubs[sid]))
    #     end
    # end
    # subs_count = Base.n_avail(new_outbox)
    # for msg in old_outbox
    #     # No need to sens subs, as they are in `nc.subs` structures before put to outbox. 
    #     if msg isa Msg || msg isa Pub || msg isa Unsub
    #         put!(new_outbox, msg)
    #     end
    # end
    # @debug "New outbox have $(Base.n_avail(new_outbox)) protocol messages including $subs_count restored subs/unsubs."
    outbox(nc, new_outbox)
end

function receiver(nc::Connection, io::IO)
    @show Threads.threadid()
    while true
        eof(io) && break
        parser_loop(io) do msg
            process(nc, msg)
        end
        # process(nc, next_protocol_message(io))
    end
    @warn "Receiver task finished at $(time())"
end

#TODO: restore link #NATS.Connect
"""
    connect([host, port; options...])

Connect to NATS server. The function is blocking until connection is initialized.

Options are:
- `default`: boolean flag that indicated if a connection should be set as default which will be used when no connection specified
- `reconnect_delays`: vector of delays that reconnect is performed until connected again, by default it will try to reconnect every second without time limit.
- `outbox_size`: size of outbox buffer for cient messages. Default is `$OUTBOX_SIZE`, if too small operations that send messages to server (e.g. `publish`) may throw an exception
- `verbose`: turns on protocol acknowledgements
- `pedantic`: turns on additional strict format checking, e.g. for properly formed subjects
- `tls_required`: indicates whether the client requires an SSL connection
- `tls_ca_cert_path`: CA certuficate file path
- `tls_client_cert_path`: client public certificate file
- `tls_client_key_path`: client private certificate file
- `auth_token`: client authorization token
- `user`: connection username
- `pass`: connection password
- `name`: client name
- `echo`: if set to `false`, the server will not send originating messages from this connection to its own subscriptions
- `jwt`: the JWT that identifies a user permissions and account.
- `no_responders`: enable quick replies for cases where a request is sent to a topic with no responders.
- `nkey`: the public NKey to authenticate the client
- `nkey_seed`: the private NKey to authenticate the client
"""
function connect(
    host::String = get(ENV, "NATS_HOST", "localhost"),
    port::Int = parse(Int, get(ENV, "NATS_PORT", "4222"));
    default = false,
    reconnect_delays = RECONNECT_DELAYS,
    outbox_size = OUTBOX_SIZE,
    options...
)
    if default && !isnothing(state.default_connection)
        dc = connection(:default)
        isdrained(dc) || error("Default connection already exists. To set new default connection or `drain` the old one first.")
    end

    options = merge(default_connect_options(), options)
    sock, read_stream, write_stream, info_msg = init_protocol(host, port, options)

    nc = Connection(; host, port, info = info_msg, outbox = Channel{ProtocolMessage}(outbox_size))
    status(nc, CONNECTED)
    # TODO: task monitoring, warn about broken connection after n reconnects.
    reconnect_task = Threads.@spawn :interactive disable_sigint() do
        @show Threads.threadid()
        while true
            receiver_task = Threads.@spawn :interactive disable_sigint() do; receiver(nc, read_stream) end
            @info "starting sender"
            sender_task = Threads.@spawn :interactive disable_sigint() do; sendloop(nc, write_stream) end

            errormonitor(receiver_task)
            errormonitor(sender_task)

            err_channel = Channel()
            bind(err_channel, receiver_task)
            bind(err_channel, sender_task)
            
            while true
                try
                    wait(err_channel)
                catch err
                    istaskfailed(receiver_task) && @error "Receiver task failed:" receiver_task.result
                    istaskfailed(sender_task) && @error "Sender task failed:" sender_task.result
                    close(nc.send_buffer)
                    @lock nc.send_buffer_cond notify(nc.send_buffer_cond)
                    @info "Wait end time: $(time())"
                    close(sock)
                    break
                end
            end
            if isdrained(nc)
                @debug "Drained, no reconnect."
                break
            end
            try wait(sender_task) catch end
            # TODO: add flag to decide at which pont reopen send buffer.
            nc.send_buffer = IOBuffer() # TODO: add sizehint
            # TODO: add subs and unsubs to send buffer first
            # try wait(receiver_task) catch end

            @warn "Reconnecting..."
            status(nc, CONNECTING)
            start_time = time()
            # TODO: handle repeating server Err messages.
            start_reconnect_time = time()
            function check_errors(s, e)
                total_retries = length(reconnect_delays)
                current_retries = total_retries - s[1]
                current_time = time() - start_reconnect_time
                mod(current_retries, 10) == 0 && @warn "Reconnect to $(clustername(nc)) cluster failed $current_retries times in $current_time seconds." e
                true
            end
            retry_init_protocol = retry(init_protocol, delays=reconnect_delays, check = check_errors)
            try
                sock, read_stream, write_stream, info_msg = retry_init_protocol(host, port, options; nc)
            catch err
                time_diff = time() - start_reconnect_time
                @error "Connection disconnected after $(length(reconnect_delays)) reconnect retries, it took $time_diff seconds." err
                status(nc, DISCONNECTED)
                break
            end
            info(nc, info_msg)
            status(nc, CONNECTED)
            # @lock nc.lock nc.stats.reconnections = nc.stats.reconnections + 1
            # @lock state.lock state.stats.reconnections = state.stats.reconnections + 1
            @info "Reconnected to $(clustername(nc)) cluster after $(time() - start_time) seconds."
        end
    end

    default && connection(:default, nc)
    @lock state.lock push!(state.connections, nc)
    nc
end
