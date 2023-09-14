const REQUEST_TIMEOUT_SECONDS = 5

"""
    request(conn, subject[, nreplies; timer])

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
function request(conn::Connection, subject::String; timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS))
    replies = request(conn, subject, 1; timer)
    isempty(replies) && error("No replies received.") 
    first(replies)
end

function request(conn::Connection, subject::String, nreplies; timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS))
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = randstring()
    replies = Channel(nreplies)
    sub = subscribe(conn, reply_to) do msg
        put!(replies, msg)
        if Base.n_avail(replies) == nreplies
            close(replies)
        end
    end
    unsubscribe(conn, sub; max_msgs = nreplies)
    publish(conn, subject; reply_to)
    @async begin 
        wait(timer)
        # To prevent a message delivery after timeout repeat unsubscribe with zero messages.
        # There is still small probablity than message will be delivered in between. In such
        # case `-NAK`` will be sent to reply subject in `connection.jl` for jetstream message.
        unsubscribe(conn, sub; max_msgs = 0)
        close(replies)
    end
    first(collect(replies), nreplies)
end

function reply(f, nc::Connection, subject::String; queue_group::Union{Nothing, String} = nothing)
    subscribe(nc, subject; queue_group) do msg
        publish(nc, msg.reply_to; payload = f(msg))
    end
end
