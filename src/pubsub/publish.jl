"""
$(SIGNATURES)

Publish message to a subject.

Optional keyword argumetns are:
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

Publish `data` to a `subject`, payload is obtained with `show` method taking $MIME_PAYLOAD, headers are obtained wth `show` method taking $MIME_HEADERS.

Optional parameters:
- `connection`: connection to be used, if not specified `default` connection is taken
- `reply_to`: subject to which a result should be published

It is equivalent to:
```
publish(subject; payload = String(repr(NATS.MIME_PAYLOAD(), data)), headers = String(repr(NATS.MIME_PAYLOAD(), data)))
````
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
        send(connection, Pub(subject, reply_to, sizeof(payload), payload))
    else
        headers_size = sizeof(headers)
        total_size = headers_size + sizeof(payload)
        send(connection, HPub(subject, reply_to, headers_size, total_size, headers, payload))
    end
end
