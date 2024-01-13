### connect.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains functions for estabilishing connection and maintaining connectivity when TCP connection fails.
#
### Code:

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
        lang = CLIENT_LANG,
        version = CLIENT_VERSION,
        protocol = 1,
        echo = nothing,
        sig = nothing,
        jwt = get(ENV, "NATS_JWT", nothing),
        no_responders = true,
        headers = true,
        nkey = get(ENV, "NATS_NKEY", nothing),
        # Options used only on client side, never sent to server.
        nkey_seed = get(ENV, "NATS_NKEY_SEED", nothing),
        tls_ca_path = get(ENV, "NATS_TLS_CA_PATH", nothing),
        tls_cert_path = get(ENV, "NATS_TLS_CERT_PATH", nothing),
        tls_key_path = get(ENV, "NATS_TLS_KEY_PATH", nothing),
        ping_interval = parse(Float64, get(ENV, "NATS_PING_INTERVAL", string(DEFAULT_PING_INTERVAL_SECONDS))),
        max_pings_out = parse(Int64, get(ENV, "NATS_MAX_PINGS_OUT", string(DEFAULT_MAX_PINGS_OUT))),
        retry_on_init_fail = parse(Bool, get(ENV, "NATS_RETRY_ON_INIT_FAIL", string(DEFAULT_RETRY_ON_INIT_FAIL))),
        ignore_advertised_servers = parse(Bool, get(ENV, "NATS_IGNORE_ADVERTISED_SERVERS", string(DEFAULT_IGNORE_ADVERTISED_SERVERS))),
        retain_servers_order = parse(Bool, get(ENV, "NATS_RETAIN_SERVERS_ORDER", string(DEFAULT_RETAIN_SERVERS_ORDER))),
        send_enqueue_when_disconnected = parse(Bool, get(ENV, "NATS_ENQUEUE_WHEN_DISCONNECTED", string(DEFAULT_ENQUEUE_WHEN_DISCONNECTED))),
        reconnect_delays = default_reconnect_delays(),
        send_buffer_limit = parse(Int, get(ENV, "NATS_SEND_BUFFER_LIMIT_BYTES", string(DEFAULT_SEND_BUFFER_LIMIT_BYTES))),
        send_retry_delays = SEND_RETRY_DELAYS,
        drain_timeout = parse(Float64, get(ENV, "NATS_DRAIN_TIMEOUT_SECONDS", string(DEFAULT_DRAIN_TIMEOUT_SECONDS))),
        drain_poll = parse(Float64, get(ENV, "NATS_DRAIN_POLL_INTERVAL_SECONDS", string(DEFAULT_DRAIN_POLL_INTERVAL_SECONDS))),
    )
end

function default_reconnect_delays()
    ExponentialBackOff(
        n = parse(Int64, get(ENV, "NATS_RECONNECT_RETRIES", string(DEFAULT_RECONNECT_RETRIES))),
        first_delay = parse(Float64, get(ENV, "NATS_RECONNECT_FIRST_DELAY", string(DEFAULT_RECONNECT_FIRST_DELAY))),
        max_delay = parse(Float64, get(ENV, "NATS_RECONNECT_MAX_DELAY", string(DEFAULT_RECONNECT_MAX_DELAY))),
        factor = parse(Float64, get(ENV, "NATS_RECONNECT_FACTOR", string(DEFAULT_RECONNECT_FACTOR))),
        jitter = parse(Float64, get(ENV, "NATS_RECONNECT_JITTER", string(DEFAULT_RECONNECT_JITTER))))
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

function host_port(url::AbstractString)
    if !contains(url, "://")
        url = "nats://$url"
    end
    uri = URI(url)
    host, port, scheme, userinfo = uri.host, uri.port, uri.scheme, uri.userinfo
    if isempty(host)
        error("Host not specified in url `$url`.")
    end
    if isempty(port)
        port = DEFAULT_PORT
    end
    host, parse(Int, port), scheme, userinfo
end

function connect_urls(nc::Connection, url; ignore_advertised_servers::Bool)
    info_msg = info(nc)
    if ignore_advertised_servers || isnothing(info_msg) || isnothing(info_msg.connect_urls) || isempty(info_msg.connect_urls)
        split(url, ",")
    else
        info_msg.connect_urls
    end
end

function init_protocol(nc, url, options)
    @atomic nc.connect_init_count += 1
    urls = connect_urls(nc, url; options.ignore_advertised_servers)
    if options.retain_servers_order
        idx = mod((@atomic nc.connect_init_count) - 1, length(urls)) + 1
        url = urls[idx]
    else
        url = rand(urls)
    end
    host, port, scheme, userinfo = host_port(url)
    if scheme == "tls"
        # Due to ADR-40 url schema can enforce TLS.
        options = merge(options, (tls_required = true,))
    end
    if !isnothing(userinfo) && !isempty(userinfo)
        user, pass = split(userinfo, ":"; limit = 2)
        if !haskey(options, :user) || isnothing(options.user)
            options = merge(options, (user = user,))
        end
        if !haskey(options, :pass) || isnothing(options.pass)
            options = merge(options, (pass = pass,))
        end
    end
    sock = Sockets.connect(host, port)
    try
        info_msg = next_protocol_message(sock)
        info_msg isa Info || error("Expected INFO, received $info_msg")
        validate_connect_options(info_msg, options)
        read_stream, write_stream = sock, sock
        if !isnothing(info_msg.tls_required) && info_msg.tls_required
            tls_options = options[(:tls_ca_path, :tls_cert_path, :tls_key_path)]
            (read_stream, write_stream) = upgrade_to_tls(sock, tls_options...)
            @debug "Socket upgraded"
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
        msg isa Union{Ok, Err, Pong, Ping} || error("Expected +OK, -ERR, PING or PONG , received $msg")
        while true
            if msg isa Ping
                show(write_stream, MIME_PROTOCOL(), Pong())
            elseif msg isa Err
                error(msg.message)
            elseif msg isa Pong
                break # This is what we waiting for.
            elseif msg isa Ok
                # Do nothing, verbose protocol.
            else
                error("Unexpected message received $msg")
            end
            msg = next_protocol_message(read_stream)
        end

        if !isnothing(nc)
            nc.url = url
        end
        sock, read_stream, write_stream, info_msg
    catch err
        close(sock)
        rethrow()
    end
end

function receiver(nc::Connection, io::IO)
    # @show Threads.threadid()
    parser_loop(io) do msg
        process(nc, msg)
    end
end

function ping_loop(nc::Connection, ping_interval::Float64, max_pings_out::Int64)
    pings_out = 0
    reconnects = (@atomic nc.reconnect_count)
    while status(nc) == CONNECTED && reconnects == (@atomic nc.reconnect_count)
        sleep(ping_interval)
        if !(status(nc) == CONNECTED && reconnects == (@atomic nc.reconnect_count))
            # In case if connection is broken new task will be spawned.
            # If another reconnect occured in meanwhile, stop this task cause another was already spawned.
            break
        end
        try
            _, tm = @timed ping(nc)
            pings_out = 0
            @debug "PONG received after $tm seconds"
        catch
            @debug "No PONG received."
            pings_out += 1
        end
        if pings_out > max_pings_out
            @warn "No pong received after $pings_out attempts."
            break
        end
    end
end

#TODO: restore link #NATS.Connect
"""
$(SIGNATURES)

Connect to NATS server. The function is blocking until connection is
initialized. In case of error during initialization process `connect` will
throw exception if `retry_on_init_fail` is set to `false` (what is default).
Otherwise handle will be returned and reconnect will continue in background.

Options are:
- `verbose`: turns on protocol acknowledgements
- `pedantic`: turns on additional strict format checking, e.g. for properly formed subjects
- `tls_required`: indicates whether the client requires SSL connection
- `tls_ca_path`: CA certuficate file path
- `tls_cert_path`: client public certificate file
- `tls_key_path`: client private certificate file
- `auth_token`: client authorization token
- `user`: connection username
- `pass`: connection password
- `name`: client name
- `echo`: if set to `false`, the server will not send originating messages from this connection to its own subscriptions
- `jwt`: the JWT that identifies a user permissions and account.
- `no_responders`: enable quick replies for cases where a request is sent to a topic with no responders.
- `nkey`: the public NKey to authenticate the client
- `nkey_seed`: the private NKey to authenticate the client
- `ping_interval`: interval in seconds how often server should be pinged to check connection health. Default is $DEFAULT_PING_INTERVAL_SECONDS seconds
- `max_pings_out`: how many pings in a row might fail before connection will be restarted. Default is `$DEFAULT_MAX_PINGS_OUT`
- `retry_on_init_fail`: if set connection handle will be returned even if initial connect fails. Otherwise error causing failure will be trown. Default is `$DEFAULT_RETRY_ON_INIT_FAIL`
- `ignore_advertised_servers`: ignores other cluster servers returned by server. Default is `$DEFAULT_IGNORE_ADVERTISED_SERVERS`
- `retain_servers_order`: try to connect server in order specified in `url` or list returned by the server. Defaylt is `$DEFAULT_RETAIN_SERVERS_ORDER`
- `send_enqueue_when_disconnected`: allows buffering outgoing messages during disconnection. Default is `$DEFAULT_ENQUEUE_WHEN_DISCONNECTED`
- `reconnect_delays`: vector of delays that reconnect is performed until connected again, by default it will try to reconnect every second without time limit.
- `send_buffer_limit`: soft limit for buffer of messages pending. Default is `$DEFAULT_SEND_BUFFER_LIMIT_BYTES` bytes, if too small operations that send messages to server (e.g. `publish`) may throw an exception
- `drain_timeout`: Timeout for drain process. After timeout in case of not everyting is processed drain will stop and error will be reported.
- `drain_poll`: Interval for `drain` to check if all messages in buffers are processed.
"""
function connect(
    url::String = get(ENV, "NATS_CONNECT_URL", DEFAULT_CONNECT_URL);
    options...
)
    options = merge(default_connect_options(), options)
    nc = Connection(;
        url,
        info = nothing,
        reconnect_count = 0,
        connect_init_count = 0,
        send_buffer_flushed = true,
        options.send_buffer_limit,
        options.send_retry_delays,
        options.send_enqueue_when_disconnected,
        options.drain_timeout,
        options.drain_poll)
    sock = nothing
    read_stream = nothing
    write_stream = nothing
    info_msg = nothing
    try
        sock, read_stream, write_stream, info_msg = init_protocol(nc, url, options)
        info(nc, info_msg)
        status(nc, CONNECTED)
    catch
        if !options.retry_on_init_fail
            rethrow()
        end
    end
    # This task just waits for `drain_even`, to wake up `reconnect_task` that there is cleanup to do.
    drain_await_task = Threads.@spawn :interactive disable_sigint() do
        wait(nc.drain_event)
    end
    # This works as controller for connection state. It spawns other task and listens for their completion to do
    # reconnect logic.
    reconnect_task = Threads.@spawn :interactive disable_sigint() do
        # @show Threads.threadid()
        while true
            if status(nc) == CONNECTING
                start_time = time()
                # TODO: handle repeating server Err messages.
                start_reconnect_time = time()
                function check_errors(s, e)
                    total_retries = length(options.reconnect_delays)
                    current_retries = total_retries - s[1]
                    current_time = time() - start_reconnect_time
                    mod(current_retries, 10) == 0 && @warn "Reconnect to $(clustername(nc)) cluster failed $current_retries times in $current_time seconds." e
                    (@atomic nc.drain_event.set) == false # Stop on drain
                end
                retry_init_protocol = retry(init_protocol, delays=options.reconnect_delays, check = check_errors)
                try
                    sock, read_stream, write_stream, info_msg = retry_init_protocol(nc, url, options)
                    status(nc, CONNECTED)
                catch err
                    time_diff = time() - start_reconnect_time
                    @error "Connection disconnected after $(nc.connect_init_count) reconnect retries, it took $time_diff seconds." err
                    if (@atomic nc.drain_event.set) == true
                        status(nc, DRAINING)
                        _do_drain(nc, false)
                        status(nc, DRAINED)
                    else
                        status(nc, DISCONNECTED)
                    end
                end
                if status(nc) == CONNECTED
                    @atomic nc.reconnect_count += 1
                    info(nc, info_msg)
                    @info "Reconnected to $(clustername(nc)) cluster on `$(nc.url)` after $(time() - start_time) seconds."
                elseif status(nc) == DISCONNECTED
                    wait(nc.reconnect_event)
                    @debug "Reconnect requested"
                    if (@atomic nc.drain_event.set) == true
                        status(nc, DRAINING)
                        _do_drain(nc, false)
                        status(nc, DRAINED)
                        break
                    else
                        status(nc, CONNECTING)
                        continue
                    end
                elseif status(nc) == DRAINED
                    break
                end
            end
            receiver_task = Threads.@spawn :interactive disable_sigint() do; receiver(nc, read_stream) end
            sender_task = Threads.@spawn :interactive disable_sigint() do; sendloop(nc, write_stream) end
            ping_task = Threads.@spawn :interactive disable_sigint() do; ping_loop(nc, options.ping_interval, options.max_pings_out) end
            reconnect_await_task = Threads.@spawn :interactive disable_sigint() do; wait(nc.reconnect_event) end

            err_channel = Channel()
            bind(err_channel, receiver_task)
            bind(err_channel, sender_task)
            bind(err_channel, ping_task)
            bind(err_channel, drain_await_task)
            bind(err_channel, reconnect_await_task)
            try
                wait(err_channel)
                @debug "Reconnect task woken at $(time())"
            catch err
                if !(err isa InvalidStateException)
                    @debug "Error caused wake up" err
                end
            end

            if istaskdone(drain_await_task)
                status(nc, DRAINING)
                # Check if there is a chance for send buffer flush.
                is_connected = !(istaskdone(sender_task) || istaskdone(receiver_task))
                _do_drain(nc, is_connected)
                status(nc, DRAINED)
                close(sock)
                reopen_send_buffer(nc)
                break
            end
            
            notify(nc.reconnect_event) # Finish reconnect_await_task.
            # TODO: maybe `autoreset` should be used, but special care needs to be taken to not consume it anywhere else.
            reset(nc.reconnect_event) # Reset event to prevent forever reconnect. 
            close(sock) # Finish receiver_task.
            reopen_send_buffer(nc) # Finish sender_task.

            try wait(sender_task) catch end
            try wait(receiver_task) catch end
            try wait(reconnect_await_task) catch end
            # `ping_task` will complete eventually seeing `reconnect_count` increased.

            @assert istaskdone(receiver_task)
            @assert istaskdone(sender_task)
            @assert istaskdone(reconnect_await_task)

            # TODO: indicate what was the cause in warning message.
            @warn "Connection to $(clustername(nc)) cluster on `$(nc.url)` lost, trynig to reconnect."
            status(nc, CONNECTING)
            @atomic nc.connect_init_count = 0
        end
    end
    errormonitor(reconnect_task)

    @lock state.lock push!(state.connections, nc)
    nc
end

"""
$(SIGNATURES)

Force a connection reconnect. If connection is `CONNECTED` this will close it
and reopen again resubscribing all existing subscriptions. If connection is
`DISCONNECTED` it will try to connect with all previously existing subscription
restored. In case connection is already `CONNECTING` this method have no effect.
If called on connection that is `DRAINING` or `DRAINED` error will be thrown.

During reconnect period some messages both published and received by the
connection might be lost.

Optional keyword aruguments:
- `should_wait`: If `true` method will block until reconnection process is started, default is `true`.
"""
function reconnect(connection::NATS.Connection; should_wait::Bool = true)
    @lock connection.status_change_cond begin
        if connection.status == DRAINING || connection.status == DRAINED
            error("Cannot reconnect a drained connection.")
        end
        notify(connection.reconnect_event)
        while should_wait && connection.status != CONNECTING
            wait(connection.status_change_cond)
        end
    end
end
