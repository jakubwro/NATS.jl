import StructTypes: omitempties

# Payload serialization.

function Base.show(io::IO, ::MIME_PAYLOAD, ::Nothing)
    # Empty payload, nothing to write.
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, ::Headers)
    # When only headers are provided, do not write any payload.
    # TODO: what if someone used Vector{Pair{String, String}} as payload?
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, payload::String)
    # Allows to return string from handler for `reply`.
    write(io, payload)
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{TPayload, Headers}) where TPayload
    # Allows to return tuple from handler, useful to override headers.
    Base.show(io, mime, first(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{TPayload, Nothing}) where TPayload
    # Handle edge case when some method will return nothing headers, but still in a tuple with payload.
    Base.show(io, mime, first(tup))
    nothing
end

# Headers serialization.

function Base.show(io::IO, ::MIME_HEADERS, ::Any)
    # Default is empty header.
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, ::Nothing)
    # Empty headers, nothing to write.
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, tup::Tuple{TPayload, Headers}) where TPayload
    Base.show(io, mime, last(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, s::String)
    startswith(s, "NATS/1.0\r\n") && write(io, s) # TODO: better validations, not sure if this method is needed.
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
    hbytes = length(pub.headers)
    nbytes = length(pub.payload)
    if hbytes > 0
        write(io, "H")
    end
    write(io, "PUB ")
    write(io, pub.subject)
    if !isnothing(pub.reply_to) && !isempty(pub.reply_to)
        write(io, " ")
        write(io, pub.reply_to)
    end
    if hbytes > 0
        write(io, " $hbytes")
    end
    write(io, " $(hbytes + nbytes)\r\n")
    write(io, pub.headers)
    write(io, pub.payload)
    write(io, "\r\n")
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
    @info "writing"
    write(io, "PING\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Pong)
    write(io, "PONG\r\n")
end
