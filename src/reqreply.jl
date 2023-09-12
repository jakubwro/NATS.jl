const REQUEST_TIMEOUT_SECONDS = 5

"""
    request(conn, subject[; nreplies, timer])

Send NATS [Request-Reply](https://docs.nats.io/nats-concepts/core-nats/reqreply) message.

If `nreplies` is grater than one vector of messages will be returned.
Default timeout is $REQUEST_TIMEOUT_SECONDS seconds which can be overriden by passing `timer`.

# Examples
```julia-repl
julia> NATS.request(nc, "help.please")
NATS.Msg("l9dKWs86", "7Nsv5SZs", nothing, 17, "OK, I CAN HELP!!!")

julia> request(nc, "help.please"; nreplies = 2, timer = Timer(0))
NATS.Msg[]
```
"""
function request(conn::Connection, subject::String; nreplies = 1, timer::Timer = Timer(REQUEST_TIMEOUT_SECONDS))
    nreplies < 1 && error("`nreplies` have to be greater than 0.")
    reply_to = randstring()
    replies = Channel{Msg}(10)
    sub, ch = subscribe(conn, reply_to) do msg
        put!(replies, msg)
        Base.n_avail(replies) >= nreplies && close(replies)
    end
    unsubscribe(conn, sub; max_msgs = nreplies)
    publish(conn, subject; reply_to)
    @async begin 
        wait(timer)
        lock(conn.lock) do
            _cleanup_sub(conn, sub.sid)
        end
        close(replies)
    end
    first(collect(replies), nreplies)
end
