

"""
$(SIGNATURES)

Reply for messages for a `subject`. Works like `subscribe` with automatic `publish` to the subject from `reply_to` field.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `queue_group`: NATS server will distribute messages across queue group members
- `async_handlers`: if `true` task will be spawn for each `f` invocation, otherwise messages are processed sequentially, default is `false`

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
    connection::Connection = connection(:default),
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
