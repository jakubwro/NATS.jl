# Logic related to msgs received from NATS server.

function default_fallback_handler(::Connection, msg::Union{Msg, HMsg})
    @warn "Unexpected message delivered." msg
end

function process(nc::Connection, info::Info)
    @debug "New INFO received."
    put!(nc.info, info)
    while Base.n_avail(nc.info) > 1
        @debug "Dropping old info"
        take!(nc.info)
    end
end

function process(nc::Connection, ping::Ping)
    @debug "Sending PONG."
    send(nc, Pong())
end

function process(nc::Connection, pong::Pong)
    @info "Received pong."
end

function process(nc::Connection, msg::Union{Msg, HMsg})
    @debug "Received $msg"
    ch = lock(state.lock) do
        c = get(state.handlers, msg.sid, nothing)
        if !isnothing(c)
            nc.stats.msgs_handled = nc.stats.msgs_handled + 1
            state.stats.msgs_handled = state.stats.msgs_handled + 1
        end
        c
    end
    if isnothing(ch)
        fallbacks = lock(state.lock) do
            collect(state.fallback_handlers)
        end
        for f in fallbacks
            Base.invokelatest(f, nc, msg)
        end
        lock(state.lock) do
            nc.stats.msgs_not_handled = nc.stats.msgs_not_handled + 1
            state.stats.msgs_not_handled = state.stats.msgs_not_handled + 1
        end
    else
        if Base.n_avail(ch) == ch.sz_max
            # TODO: drop old msgs?
        else
            put!(ch, msg)
        end
        _cleanup_unsub_msg(nc, msg.sid)
    end
end

function process(nc::Connection, ok::Ok)
    @debug "Received OK."
end

function process(nc::Connection, err::Err)
    @error "NATS protocol error!" err
end
