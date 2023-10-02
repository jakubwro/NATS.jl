

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
    subject::String;
    connection::Connection = default_connection(),
    queue_group::Union{Nothing, String} = nothing,
    async_handlers = false
)
    T = argtype(f)
    find_msg_conversion_or_throw(T)
    fast_f = _fast_call(f, T)
    subscribe(subject; connection, queue_group, async_handlers) do msg
        data = fast_f(msg)
        publish(msg.reply_to, data; connection)
    end
end
