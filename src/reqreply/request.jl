"""
$(SIGNATURES)

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

Default timeout is $REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `timer`: error will be thrown if no replies received until `timer` expires

# Examples
```julia-repl
julia> NATS.request("help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, 17, "OK, I CAN HELP!!!")

julia> request("help.please"; timer = Timer(0))
ERROR: No replies received.
```
"""
function request(
    subject::String,
    data = nothing;
    connection::Connection = connection(:default),
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    replies = request(subject, data, 1; connection, timer)
    if isempty(replies) || all(has_error_status, replies)
        error("No replies received.")
    end
    first(replies)
end

function has_error_status(msg::NATS.Message)
    statuscode(msg) in 400:599
end

"""
$(SIGNATURES)

Requests for multiple replies. Vector of messages is returned after receiving `nreplies` replies or timer expired.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `timer`: error will be thrown if no replies received until `timer` expires

# Examples
```julia-repl
julia> request("help.please", nreplies = 2; timer = Timer(0))
NATS.Msg[]
```
"""
function request(
    subject::String,
    data,
    nreplies::Integer;
    connection::Connection = connection(:default),
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    find_data_conversion_or_throw(typeof(data))
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = @lock NATS.state.lock randstring(connection.rng, 20)
    replies = Channel(nreplies)
    sub = subscribe(reply_to; async_handlers = false, connection) do msg
        try
            put!(replies, msg)
            if Base.n_avail(replies) == nreplies || has_error_status(msg)
                close(replies)
            end
        catch err
            @warn "Error from subscribe" err
            # TODO: send `nak` if jetstream message.
        end
    end
    unsubscribe(sub; connection, max_msgs = nreplies)
    publish(subject, data; connection, reply_to)
    bind(replies, @async wait(timer))
    received = first(collect(replies), nreplies)
    unsubscribe(sub; connection, max_msgs = 0)
    @debug "Received $(length(received)) messages with statuses: $(map(m -> statuscode(m), received))"
    received
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    connection::Connection = connection(:default),
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    result = request(subject, data; connection, timer)
    convert(T, result)
end
