"""
$(SIGNATURES)

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

Default timeout is $REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`.

# Examples
```julia-repl
julia> NATS.request("help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, 17, "OK, I CAN HELP!!!")

julia> request("help.please"; timer = Timer(0))
ERROR: No replies received.

julia> request("help.please", nreplies = 2; timer = Timer(0))
NATS.Msg[]
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
    sub = subscribe(reply_to; connection) do msg
        put!(replies, msg)
        if Base.n_avail(replies) == nreplies || has_error_status(msg)
            close(replies)
        end
    end
    unsubscribe(sub; connection, max_msgs = nreplies)
    publish(subject, data; connection, reply_to)
    Threads.@spawn :default begin 
        wait(timer)
        # To prevent a message delivery after timeout repeat unsubscribe with zero messages.
        # There is still small probablity than message will be delivered in between. In such
        # case `-NAK`` will be sent to reply subject in `connection.jl` for jetstream message.
        # TODO: allow for registering custom handler of such case.
        unsubscribe(sub; connection, max_msgs = 0)
        close(replies)
    end
    received = first(collect(replies), nreplies)
    # TODO: nak remaining messages? log warning?
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
