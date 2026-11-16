const NEXT_EXPIRES = 500 * 1000 * 1000 # 500 ms, TODO: add to env

"""
$(SIGNATURES)

Get next message for a consumer.
"""
function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo, batch::Int64; no_wait = false, no_throw = false)
    batch > 0 || throw(ArgumentError("`batch` must be greater than 0."))
    req = Dict()
    req[:no_wait] = no_wait
    req[:batch] = batch
    if !no_wait
        req[:expires] = NEXT_EXPIRES
    end
    subject = "\$JS.API.CONSUMER.MSG.NEXT.$(consumer.stream_name).$(consumer.name)"
    while true
        msgs = pull(connection, batch, subject, JSON3.write(req))
        ok = filter(!NATS.has_error_status, msgs)
        !isempty(ok) && return ok
        err = filter(NATS.has_error_status, msgs)
        critical = filter(m -> NATS.statuscode(m) != 408, err)
        # 408 indicates timeout
        if !isempty(critical)
            for msg in Iterators.drop(critical, 1)
                code, message = NATS.statusinfo(msg)
                @warn "Consumer next returned an additional error." code message
            end
            no_throw || NATS.throw_on_error_status(first(critical))
            return critical
        end
    end
end

function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo; no_wait = false, no_throw = false)
    batch = consumer_next(connection, consumer, 1; no_wait, no_throw)
    only(batch)
end

# Pulled messages keep the subject they were stored with, so they cannot come to the request inbox, which tells requests
# apart by the subject. A pull has its own subscription instead. Returns up to `batch` messages, the last one can be the
# status that ended the pull, or none if nothing came in time.
function pull(connection::NATS.Connection, batch::Int64, subject::String, data::String)
    if NATS.status(connection) in (NATS.DRAINED, NATS.DRAINING)
        throw(NATS.NATSError(499, "Connection is drained."))
    end
    timeout = parse(Float64, get(ENV, "NATS_REQUEST_TIMEOUT_SECONDS", string(NATS.DEFAULT_REQUEST_TIMEOUT_SECONDS)))
    random_suffix = @lock connection.lock randstring(connection.rng, 10)
    sub = NATS.subscribe(connection, "$(connection.inbox_prefix).$random_suffix")
    NATS.unsubscribe(connection, sub; max_msgs = batch)
    # Unsubscribing ends `next` waiting for a message, a drain unsubscribes by itself. The timer and the end of the pull
    # both call this, under `send_buffer_cond` only the first finds the channel open and no drain finishes meanwhile.
    unsubscribe_if_subscribed() = @lock connection.send_buffer_cond begin
        sub_data = @lock connection.lock get(connection.sub_data, sub.sid, nothing)
        !isnothing(sub_data) && isopen(sub_data.channel) && NATS.unsubscribe(connection, sub)
    end
    timer = Timer(_ -> unsubscribe_if_subscribed(), timeout)
    msgs = NATS.Msg[]
    try
        NATS.publish(connection, subject, data; reply_to = sub.subject)
        for _ in 1:batch
            msg = NATS.next(connection, sub; no_throw = true)
            isnothing(msg) && break # Unsubscribed on timeout or drain.
            push!(msgs, msg)
            NATS.has_error_status(msg) && break # An error status ends the pull.
        end
    finally
        close(timer)
        # The server removes the subscription after `batch` messages, a pull that ended earlier unsubscribes.
        length(msgs) < batch && unsubscribe_if_subscribed()
    end
    msgs
end
