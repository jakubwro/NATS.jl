function _try_next_until_drained(stream, consumer; connection)
    msg = nothing
    while !isdrained(connection)
        timer = Timer(5)
        try
            msg = next(stream, consumer; connection, timer)
            break
        catch err
            if err isa InterruptException
                rethrow()
            end
            @debug "Error on `next`" stream consumer err
            isopen(timer) && try wait(timer) catch end
        end
    end
    if isnothing(msg)
        @assert isdrained(connection) "The only reason for `nothing` message should be draining the connection."
        error("Connection is draining.")
    end
    msg
end

@enum WorkerState IDLE BUSY PAUSED

mutable struct WorkerMetrics
    @atomic is_working::Bool
    @atomic idle_time::Int64
    @atomic busy_time::Int64
end

const WORKER_METRICS = Dict{String, WorkerMetrics}()

# function worker_metrics()

# end

function worker(
    f,
    stream::String,
    consumer::String;
    reply_to::Union{String, Nothing} = nothing,
    name::Union{Nothing, String} = nothing,
    connection::NATS.Connection)
    
    while true # TODO: while connection is not drained
        msg = _try_next_until_drained(stream, consumer; connection)
        # If connection is about to be closed, return message to the stream immediately.
        if isdrained(connection)
            !isnothing(msg) && nak(msg; connection)
            break
        end
        @assert !isnothing(msg)
        try
            result = f(msg)
            if !isnothing(reply_to)
                publish(reply_to, result; connection)
            end
            ack(msg; connection)
        catch err
            @error "Error during message processing." stream consumer msg err
            nak(msg; connection)
        end
    end
end

# TODO: draining of subs not implemented yet.
