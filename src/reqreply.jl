const REQUEST_TIMEOUT_SECONDS = 5

"""
$(SIGNATURES)

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

Default timeout is $REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`.

# Examples
```julia-repl
julia> NATS.request(nc, "help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, 17, "OK, I CAN HELP!!!")

julia> request(nc, "help.please"; timer = Timer(0))
ERROR: No replies received.

julia> request(nc, "help.please", nreplies = 2; timer = Timer(0))
NATS.Msg[]
```
"""
function request(
    nc::Connection,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    replies = request(nc, subject, data, 1; timer)
    if isempty(replies) || all(has_error_status, replies)
        error("No replies received.")
    end
    first(replies)
end

function request(
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(default_connection(), subject, data; timer)
end

function has_error_status(msg::NATS.Message)
    statuscode(msg) in 400:599
end

function request(
    nc::Connection,
    subject::String,
    data,
    nreplies::Integer;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = @lock NATS.state.lock randstring(nc.rng, 20)
    replies = Channel(nreplies)
    sub = subscribe(nc, reply_to) do msg
        put!(replies, msg)
        if Base.n_avail(replies) == nreplies || has_error_status(msg)
            close(replies)
        end
    end
    unsubscribe(nc, sub; max_msgs = nreplies)
    publish(nc, subject, data; reply_to)
    @async begin 
        wait(timer)
        # To prevent a message delivery after timeout repeat unsubscribe with zero messages.
        # There is still small probablity than message will be delivered in between. In such
        # case `-NAK`` will be sent to reply subject in `connection.jl` for jetstream message.
        # TODO: allow for registering custom handler of such case.
        unsubscribe(nc, sub; max_msgs = 0)
        close(replies)
    end
    received = first(collect(replies), nreplies)
    # TODO: nak remaining messages? log warning?
    @debug "Received $(length(received)) messages with statuses: $(map(m -> statuscode(m), received))"
    received
end

"""
$(SIGNATURES)

The same as above but uses implicit connection (this functionality to be defined yet).
"""
function request(
    subject::String,
    data,
    nreplies;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    request(default_connection(), subject, data, nreplies; timer)
end

function request(
    T::Type,
    nc::Connection,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    result = request(nc, subject, data; timer)
    convert(T, result)
end

function request(
    T::Type,
    subject::String,
    data = nothing;
    timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS)
)
    result = request(default_connection(), subject, data; timer)
    convert(T, result)
end


"""
Reply for messages for a subject. Works like `subscribe` with automatic `publish` to the subject from `reply_to` field.

$(SIGNATURES)

# Examples
```julia-repl
julia> sub = reply("FOO.REQUESTS") do msg
    "This is a reply payload."
end
NATS.Sub("FOO.REQUESTS", nothing, "jdnMEcJN")

julia> sub = reply("FOO.REQUESTS") do msg
    "This is a reply payload.", ["example_header" => "This is a header value"]
end
NATS.Sub("FOO.REQUESTS", nothing, "jdnMEcJN")

julia> unsubscribe(sub)
```
"""
function reply(
    f,
    nc::Connection,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    info = false
)
    T = argtype(f)
    find_msg_conversion_or_throw(T)
    req_count = Threads.Atomic{Int}(1)
    subscribe(nc, subject; queue_group) do msg
        cnt = Threads.atomic_add!(req_count, 1)
        info && @info "[#$(cnt)] received on subject $(msg.subject)"
        data = f(convert(T, msg))
        info && @info "[#$(cnt)] replying on subject $(msg.reply_to)"
        publish(nc, msg.reply_to, data)
    end
end

"""
The same as above but uses implicit connection (this functionality to be defined yet).

$(SIGNATURES)

# Examples
```julia-repl
julia> nc = NATS.connect()
NATS.Connection(CONNECTED, 0 subs, 0 unsubs, 0 outbox)

julia> sub = reply(nc, "FOO.REQUESTS") do msg
    "This is a reply payload."
end
```
"""
function reply(
    f,
    subject::String;
    queue_group::Union{Nothing, String} = nothing,
    info = false
)
    reply(f, default_connection(), subject; queue_group, info)
end
