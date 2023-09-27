function trynext(stream, consumer; connection)
    msg = nothing
    while true # TODO: while connection is not drained
        timer = Timer(10)
        try
            msg = next(stream, consumer; connection, timer)
            break
        catch err
            @debug "Error on `next`" stream consumer err
            isopen(timer) && wait(timer) # TODO: this is not thread safe, timer can expire in beetwien `isopen` and `wait`
        end
    end
    msg
end

function worker(f, stream::String, consumer::String; connection::NATS.Connection)
    while true # TODO: while connection is not dreained
        msg = trynext(stream, consumer; connection)
        try
            result = f(msg)
            ack(msg; connection)
            # TODO: publish result to stream of KV.
        catch err
            @error "Error during message processing." stream consumer err
        end
    end
end

# TODO: draining of subs not implemented yet.
