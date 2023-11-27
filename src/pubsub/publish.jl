"""
$(SIGNATURES)

Publish message to a subject.

Optional keyword arguments are:
- `connection`: connection to be used, if not specified `default` connection is taken
- `reply_to`: subject to which a result should be published
- `payload`: payload string
- `headers`: vector of pair of string
"""
function publish(
    subject::String;
    connection::Connection = connection(:default),
    reply_to::Union{String, Nothing} = nothing,
    payload::Union{String, Nothing} = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(subject, (payload, headers); connection, reply_to)
end

"""
$(SIGNATURES)

Publish `data` to a `subject`, payload is obtained with `show` method taking `mime` `$(MIME_PAYLOAD())`, headers are obtained wth `show` method taking `mime` `$(MIME_HEADERS())`.

Optional parameters:
- `connection`: connection to be used, if not specified `default` connection is taken
- `reply_to`: subject to which a result should be published

It is equivalent to:
```
    publish(
        subject;
        payload = String(repr(NATS.MIME_PAYLOAD(), data)),
        headers = String(repr(NATS.MIME_PAYLOAD(), data)))
```
"""
function publish(
    subject::String,
    data;
    connection::Connection = connection(:default),
    reply_to::Union{String, Nothing} = nothing
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    payload = isempty(payload_bytes) ? nothing : String(payload_bytes)
    headers_bytes = repr(MIME_HEADERS(), data)
    headers = isempty(headers_bytes) ? nothing : String(headers_bytes)

    # TODO: validate with connection.info.max_payload
    if isnothing(headers)
        @lock connection.send_buffer_lock begin
            write(connection.send_buffer, "PUB ")
            write(connection.send_buffer, subject)
            if !isnothing(reply_to)
                write(connection.send_buffer, " ")
                write(connection.send_buffer, reply_to)
            end
            write(connection.send_buffer, " $(ncodeunits(payload))")
            write(connection.send_buffer, "\r\n")
            write(connection.send_buffer, payload)
            write(connection.send_buffer, "\r\n")
            # @show String(take!(connection.send_buffer))
        end
    else
        headers_size = sizeof(headers)
        total_size = headers_size + sizeof(payload)
        send(connection, HPub(subject, reply_to, headers_size, total_size, headers, payload))
    end

    @inc_stat :msgs_published 1 connection.stats state.stats
    t = current_task()
    if !isnothing(t.storage) && haskey(t.storage, "sub_stats")
        sub_stats = task_local_storage("sub_stats")
        @inc_stat :msgs_published 1 sub_stats
    end
    
    
end
