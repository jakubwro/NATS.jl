function send(nc::Connection, message::ProtocolMessage)
    if isdrained(nc)
        if message isa Unsub || message isa Pong
            status(nc) == DRAINED && error("Connection is drained.")
        else
            error("Connection is drained.")
        end
    end

    # When connection is lost outbox might be closed. Retry until new outbox is there.
    delays = vcat(0.001, 0.01, repeat([0.1], 100))
    retry(() -> put!(outbox(nc), message); delays)()
end

const buffer = ProtocolMessage[]

function sendloop(nc::Connection, io::IO)
    try
        mime = MIME_PROTOCOL()
        outbox_channel = outbox(nc)
        to_resend = collect(buffer)
        !isempty(to_resend) && @warn "Buffer has $(length(to_resend)) msgs"
        while isopen(outbox_channel)
            fetch(outbox_channel) # Wait untill some messages are there.
            empty!(buffer)
            buf = IOBuffer() # Buffer write to avoid often task yield.
            pending = Base.n_avail(outbox_channel)
            batch = min(pending, 5000)
            @assert batch > 0
            # for msg in to_resend
            #     show(buf, mime, msg)
            # end
            empty!(to_resend)
            # send_buf = []
            for _ in 1:batch
                msg = take!(outbox_channel)
                push!(buffer, msg)
                # push!(send_buf, msg)
                if msg isa Unsub && !isnothing(msg.max_msgs) && msg.max_msgs > 0 # TODO: make more generic handler per msg type
                    @lock state.lock begin nc.unsubs[msg.sid] = msg.max_msgs end # TODO: move it somewhere else
                end
                show(buf, mime, msg)
            end
            write(io, take!(buf))
            flush(io)
        end
        @info "Sender task finished, $(Base.n_avail(outbox_channel)) msgs in outbox."
    catch err
        if err isa InvalidStateException
            # This is fine, outbox closed by reconnect loop.
        else
            rethrow()
            # If task errors on write, maybe msgs should be resend
        end
    end
end
