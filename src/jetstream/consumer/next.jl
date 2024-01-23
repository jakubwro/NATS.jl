const NEXT_EXPIRES = 500 * 1000 * 1000 # 500 ms, TODO: add to env

function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo, batch::Int64; no_wait = false)
    req = Dict()
    req[:no_wait] = no_wait
    req[:batch] = batch
    if !no_wait
        req[:expires] = NEXT_EXPIRES
    end
    subject = "\$JS.API.CONSUMER.MSG.NEXT.$(consumer.stream_name).$(consumer.name)"
    while true
        msgs = NATS.request(connection, batch, subject, JSON3.write(req))
        ok = filter(m -> NATS.statuscode(m)  < 400, msgs)
        !isempty(ok) && return ok
        err = filter(m -> NATS.statuscode(m) >= 400, msgs)
        critical = filter(m -> NATS.statuscode(m) != 408, err)
        # 408 indicates timeout
        if !isempty(critical)
            # TODO warn other errors if any
            throw(NATS.NATSError(NATS.statuscode(first(critical)), ""))
        end
    end
end

function consumer_next(connection::NATS.Connection, consumer::ConsumerInfo; no_wait = false)
    batch = consumer_next(connection, consumer, 1; no_wait)
    only(batch)
end