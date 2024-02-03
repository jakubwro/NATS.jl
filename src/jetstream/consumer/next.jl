const NEXT_EXPIRES = 500 * 1000 * 1000 # 500 ms, TODO: add to env

"""
$(SIGNATURES)

Get next message for a consumer.
"""
function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo, batch::Int64; no_wait = false, no_throw = false)
    req = Dict()
    req[:no_wait] = no_wait
    req[:batch] = batch
    if !no_wait
        req[:expires] = NEXT_EXPIRES
    end
    subject = "\$JS.API.CONSUMER.MSG.NEXT.$(consumer.stream_name).$(consumer.name)"
    while true
        msgs = NATS.request(connection, batch, subject, JSON3.write(req))
        ok = filter(!NATS.has_error_status, msgs)
        !isempty(ok) && return ok
        err = filter(NATS.has_error_status, msgs)
        critical = filter(m -> NATS.statuscode(m) != 408, err)
        # 408 indicates timeout
        if !isempty(critical)
            # TODO warn other errors if any
            no_throw || NATS.throw_on_error_status(first(critical))
            return critical
        end
    end
end

function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo; no_wait = false, no_throw = false)
    batch = consumer_next(connection, consumer, 1; no_wait, no_throw)
    only(batch)
end