const REQUEST_TIMEOUT_SECONDS = 5

"""
    request(subject[, nreplies; timer, nc])

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

Default timeout is $REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`.

# Examples
```julia-repl
julia> NATS.request("help.please"; nc)
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, 17, "OK, I CAN HELP!!!")

julia> request("help.please"; timer = Timer(0), nc)
ERROR: No replies received.

julia> request("help.please", nreplies = 2; timer = Timer(0), nc)
NATS.Msg[]
```
"""
function request(
    subject::String, data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS),
    nc = default_connection()
)
    replies = request(subject, data, 1; timer, nc)
    isempty(replies) && error("No replies received.") 
    first(replies)
end

function request(
    subject::String,
    data,
    nreplies;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS),
    nc = default_connection()
)
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = randstring(nc.rng, 20)
    replies = Channel(nreplies)
    sub = subscribe(reply_to; nc) do msg
        put!(replies, msg)
        if Base.n_avail(replies) == nreplies || statuscode(msg) == 503
            close(replies)
        end
    end
    unsubscribe(sub; max_msgs = nreplies, nc)
    publish(subject, data; reply_to, nc)
    @async begin 
        wait(timer)
        # To prevent a message delivery after timeout repeat unsubscribe with zero messages.
        # There is still small probablity than message will be delivered in between. In such
        # case `-NAK`` will be sent to reply subject in `ncection.jl` for jetstream message.
        unsubscribe(sub; max_msgs = 0, nc)
        close(replies)
    end
    received = first(collect(replies), nreplies)
    if length(received) == 1 && statuscode(only(received)) == 503
        error("No responders.") 
    end
    received
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    nc::Connection = default_connection()
)
    result = request(subject, data; nc)
    convert(T, result)
end

"""
    reply(f, nc, subject[; queue_group])

Reply for messages for a subject. Works like `subscribe` with automatic `publish` to the subject from `reply_to` field.

# Examples
```julia-repl
julia> sub = reply("FOO.REQUESTS") do msg; "This is a reply." end
NATS.Sub("FOO.REQUESTS", nothing, "jdnMEcJN")

julia> unsubscribe(sub)
```
"""
function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    info = false,
    nc = default_connection()
)
    T = argtype(f)
    find_msg_conversion_or_throw(T)
    req_count = Threads.Atomic{Int}(1)
    subscribe(subject; nc, queue_group) do msg
        cnt = Threads.atomic_add!(req_count, 1)
        info && @info "[#$(cnt)] received on subject $(msg.subject)"
        data = f(convert(T, msg))
        info && @info "[#$(cnt)] replying on subject $(msg.reply_to)"
        publish(msg.reply_to, data; nc)
    end
end
