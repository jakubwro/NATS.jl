"""
$(SIGNATURES)

Publish message to a subject.
"""
function publish(
    subject::String;
    connection::Connection = default_connection(),
    reply_to::Union{String, Nothing} = nothing,
    payload = nothing,
    headers::Union{Nothing, Headers} = nothing
)
    publish(subject, (payload, headers); connection, reply_to)
end

function publish(
    subject::String,
    data;
    connection::Connection = default_connection(),
    reply_to::Union{String, Nothing} = nothing
)
    payload_bytes = repr(MIME_PAYLOAD(), data)
    payload = isempty(payload_bytes) ? nothing : String(payload_bytes)
    headers_bytes = repr(MIME_HEADERS(), data)
    headers = isempty(headers_bytes) ? nothing : String(headers_bytes)

    if isnothing(headers)
        send(connection, Pub(subject, reply_to, sizeof(payload), payload))
    else
        headers_size = sizeof(headers)
        total_size = headers_size + sizeof(payload)
        send(connection, HPub(subject, reply_to, headers_size, total_size, headers, payload))
    end
end
