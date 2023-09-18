import StructTypes: omitempties

# Payload serialization.

function Base.show(io::IO, ::MIME_PAYLOAD, ::Nothing)
    # Empty payload, nothing to write.
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, ::Headers)
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, payload::String)
    write(io, payload)
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{TPayload, Headers}) where TPayload
    Base.show(io, mime, first(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{Headers, TPayload}) where TPayload
    Base.show(io, mime, last(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{TPayload, Nothing}) where TPayload
    Base.show(io, mime, first(tup))
    nothing
end

# Headers serialization.

function Base.show(io::IO, mime::MIME_HEADERS, tup::Tuple{TPayload, Headers}) where TPayload
    Base.show(io, mime, last(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, tup::Tuple{Headers, TPayload}) where TPayload
    Base.show(io, mime, first(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, tup::Tuple{TPayload, Nothing}) where TPayload
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, ::Nothing)
    # Empty headers, nothing to write.
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, s::String)
    startswith(s, "NATS/1.0\r\n") && write(io, s) # TODO: better validations.
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, headers::Headers)
    print(io, "NATS/1.0\r\n")
    for (key, value) in headers
        print(io, key)
        print(io, ": ")
        print(io, value)
        print(io, "\r\n")
    end
    print(io, "\r\n")
    nothing
end

# Protocol serialization.

StructTypes.omitempties(::Type{Connect}) = true

function show(io::IO, ::MIME_PROTOCOL, connect::Connect)
    write(io, "CONNECT $(JSON3.write(connect))\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, pub::Pub)
    payload = isnothing(pub.payload) ? "" : pub.payload
    nbytes = sizeof(payload)
    reply_to = isnothing(pub.reply_to) ? "" : " $(pub.reply_to)"
    write(io, "PUB $(pub.subject)$reply_to $nbytes\r\n$(payload)\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, hpub::HPub)
    hbytes = sizeof(hpub.headers)
    pbytes = sizeof(hpub.payload)
    nbytes = pbytes + hbytes
    reply_to = isnothing(hpub.reply_to) ? "" : " $(hpub.reply_to)"
    write(io, "HPUB $(hpub.subject)$reply_to $hbytes $nbytes\r\n$(hpub.headers)$(hpub.payload)\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, sub::Sub)
    queue_group = isnothing(sub.queue_group) ? "" : " $(sub.queue_group)"
    write(io, "SUB $(sub.subject)$queue_group $(sub.sid)\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Unsub)
    max_msgs = isnothing(unsub.max_msgs) ? "" : " $(unsub.max_msgs)"
    write(io, "UNSUB $(unsub.sid)$max_msgs\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Ping) 
    write(io, "PING\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Pong)
    write(io, "PONG\r\n")
end
