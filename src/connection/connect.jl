
#TODO: restore link #NATS.Connect
"""
    connect([host, port; kw...])
Initialize and return `Connection`.
See `Connect protocol message`.
"""
function connect(host::String = NATS_HOST, port::Int = NATS_PORT; default = true, cert_file = nothing, key_file = nothing, kw...)
    if default && !isnothing(state.default_connection)
        return default_connection()
    end
    nc = Connection()
    connect_msg = from_kwargs(Connect, DEFAULT_CONNECT_ARGS, kw)
    spawn_sticky_task(() ->  while true reconnect(nc, host, port, connect_msg) end)

    if default
        lock(state.lock) do; state.default_connection = nc end
    else
        lock(state.lock) do; push!(state.connections, nc) end
    end
    nc
end
