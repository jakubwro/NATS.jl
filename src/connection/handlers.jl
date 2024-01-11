### handlers.jl
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
# This file contains logic related to processing messages received from NATS server.
#
### Code:

function process(nc::Connection, msg::Info)
    @debug "New INFO received: ." msg
    info(nc, msg)

    if !isnothing(msg.ldm) && msg.ldm
        @warn "Server is in Lame Duck Mode, forcing reconnect to other server"
        @debug "Connect urls are: $(msg.connect_urls)"
        # TODO: do not reconnect if there are no urls provided
        reconnect(nc, wait = false)
    end
end

function process(nc::Connection, ::Ping)
    @debug "Sending PONG."
    send(nc, Pong())
end

function process(nc::Connection, ::Pong)
    @debug "Received pong."
    @lock nc.pong_received_cond notify(nc.pong_received_cond)
end

function process(nc::Connection, batch::Vector{ProtocolMessage})
    groups = Dict{String, Vector{Msg}}()
    for msg in batch
        if msg isa Msg
            arr = get(groups, msg.sid, nothing)
            if isnothing(arr)
                arr = Msg[]
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
        sub_data = @lock nc.lock get(nc.sub_data, sid, nothing)
        if !isnothing(sub_data)
            sub_stats = sub_data.stats
            max_msgs = sub_data.channel.sz_max 
            n_dropped = sub_stats.msgs_pending + n - max_msgs
            if n_dropped > 0
                inc_stats(:msgs_dropped, n_dropped, state.stats, nc.stats, sub_stats)
                n -= n_dropped
                msgs = first(msgs, n)
                # TODO: send NAK for dropped messages
            end
            if n > 0
                try
                    inc_stats(:msgs_pending, n, state.stats, nc.stats, sub_stats)
                    put!(sub_data.channel, msgs)
                    inc_stats(:msgs_received, n, state.stats, nc.stats, sub_stats)
                catch
                    # TODO: if msg needs ack send nak here
                    # Channel was closed by `unsubscribe`.
                    dec_stats(:msgs_pending, n, state.stats, nc.stats, sub_stats)
                    inc_stats(:msgs_dropped, n, state.stats, nc.stats, sub_stats)
                end
                # TODO: here should be n + n_dropped
                _update_unsub_counter(nc, sid, n)
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
            inc_stats(:msgs_dropped, n, state.stats, nc.stats)
        end
    end
end

function process(nc::Connection, ok::Ok)
    @debug "Received OK."
end

function process(nc::Connection, err::Err)
    @error "NATS protocol error!" err
end
