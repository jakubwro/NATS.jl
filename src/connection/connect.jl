
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
    spawn_sticky_task(() ->  while true reconnect(nc, host, port, connect_msg; sock, read_stream, write_stream) end)

    if default
        lock(state.lock) do; state.default_connection = nc end
    else
        lock(state.lock) do; push!(state.connections, nc) end
    end
    nc
end
