
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
    reconnect_task = Threads.Task(() ->  while true reconnect(nc, host, port, connect_msg) end)
    # Setting sticky flag to false makes processing 10x slower when running with multiple threads.
    # reconnect_task.sticky = false
    Base.Threads._spawn_set_thrpool(reconnect_task, :default)
    Base.Threads.schedule(reconnect_task)
    errormonitor(reconnect_task)

    # TODO: refactor
    # 1. init socket
    # 2. run parser
    # 3. reconnect

    # connection_info = fetch(nc.info)
    # @info "Info: $connection_info."
    if default
        lock(state.lock) do; state.default_connection = nc end
    else
        lock(state.lock) do; push!(state.connections, nc) end
    end
    nc
end
