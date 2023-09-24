function trynext(stream, consumer; connection)
    msg = nothing
    while true # TODO: while connection is not drained
        timer = Timer(10)
        try
            msg = next(stream, consumer; connection, timer)
            break
        catch err
            @debug "Error on `next`" stream consumer err
            wait(timer)
        end
    end
    msg
end

function worker(f, stream::String, consumer::String; connection::NATS.Connection)
    while true # TODO: while connection is not dreained
        msg = trynext(stream, consuler; connection)
        try
            result = f(msg)
            ack(msg; connection)
            # TODO: publish result to stream of KV.
        catch err
            @error "Error during message processing." stream consumer err
        end
    end
end
