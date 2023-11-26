# Logic related to msgs received from NATS server.

function process(nc::Connection, msg::Info)
    @info "New INFO received: ." msg
    info(nc, msg)

    if !isnothing(msg.ldm) && msg.ldm
        @warn "Server is in Lame Duck Mode, forcing reconnect to other server"
        @info "Connect urls are: $(msg.connect_urls)"
        close(outbox(nc))
    end
end

function process(nc::Connection, ping::Ping)
    @debug "Sending PONG."
    send(nc, Pong())
end

function process(nc::Connection, pong::Pong)
    @info "Received pong."
end

function process(nc::Connection, batch::Vector{ProtocolMessage})
    groups = Dict{String, Vector{Message}}()
    for msg in batch
        if msg isa Message
            arr = get(groups, msg.sid, nothing)
            if isnothing(arr)
                arr = Message[]
                groups[msg.sid] = arr
            end
            push!(arr, msg)
        else
            process(nc, msg)
        end
    end

    fallbacks = nothing
    for (sid, msgs) in groups
        n = length(msgs)
        ch = lock(state.lock) do
            get(state.handlers, sid, nothing)
        end
        if !isnothing(ch)
            sub_stats = state.sub_stats[sid]
            if Base.n_avail(ch) == ch.sz_max
                # This check is safe, as the only task putting in to subs channel is this one.
                # TODO: drop older msgs?
                @inc_stat :msgs_dropped n state.stats nc.stats sub_stats
            else
                try
                    put!(ch, msgs)
                    @inc_stat :msgs_received n state.stats nc.stats sub_stats
                catch
                    # TODO: if msg needs ack send nak here
                    # Channel was closed by `unsubscribe`.
                    @inc_stat :msgs_dropped n state.stats nc.stats sub_stats
                end
            end
        else
            if isnothing(fallbacks)
                fallbacks = lock(state.lock) do
                    collect(state.fallback_handlers)
                end
            end
            for f in fallbacks
                for msg in msgs
                    Base.invokelatest(f, nc, msg)
                end
            end
            @inc_stat :msgs_dropped n state.stats nc.stats
        end
    end
end

function process(nc::Connection, msg::Union{Msg, HMsg})
    ch = lock(state.lock) do
        get(state.handlers, msg.sid, nothing)
    end
    if isnothing(ch)
        fallbacks = lock(state.lock) do
            collect(state.fallback_handlers)
        end
        for f in fallbacks
            Base.invokelatest(f, nc, msg)
        end
        @inc_stat :msgs_dropped 1 state.stats nc.stats
    else
        sub_stats = state.sub_stats[msg.sid]
        if Base.n_avail(ch) == ch.sz_max
            # This check is safe, as the only task putting in to subs channel is this one.
            # TODO: drop older msgs?
            @inc_stat :msgs_dropped 1 state.stats nc.stats sub_stats
        else
            try
                put!(ch, msg)
                @inc_stat :msgs_received 1 state.stats nc.stats sub_stats
            catch
                # TODO: if msg needs ack send nak here
                # Channel was closed by `unsubscribe`.
                @inc_stat :msgs_dropped 1 state.stats nc.stats sub_stats
            end
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
