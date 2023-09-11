import StructTypes: omitempties

StructTypes.omitempties(::Type{Connect}) = true

function serialize(connect::Connect)
    "CONNECT $(JSON3.write(connect))\r\n"
end

function serialize(pub::Pub)
    nbytes = ncodeunits(pub.payload)
    reply_to = isnothing(pub.reply_to) ? "" : " $(pub.reply_to)"
    "PUB $(pub.subject)$reply_to $nbytes\r\n$(pub.payload)\r\n"
end

function serialize(hpub::HPub)
    hbytes = ncodeunits(hpub.headers)
    pbytes = ncodeunits(hpub.payload)
    nbytes = pbytes + hbytes
    reply_to = isnothing(hpub.reply_to) ? "" : " $(hpub.reply_to)"
    "HPUB $(hpub.subject)$reply_to $hbytes $nbytes\r\n$(hpub.headers)$(hpub.payload)\r\n"
end

function serialize(sub::Sub)
    queue_group = isnothing(sub.queue_group) ? "" : " $(sub.queue_group)"
    "SUB $(sub.subject)$queue_group $(sub.sid)\r\n"
end

function serialize(unsub::Unsub)
    max_msgs = isnothing(unsub.max_msgs) ? "" : " $(unsub.max_msgs)"
    "UNSUB $(unsub.sid)$max_msgs\r\n"
end

function serialize(unsub::Ping) 
    "PING\r\n"
end

function serialize(unsub::Pong)
    "PONG\r\n"
end

function serialize_header(::Nothing)
    ""
end

function serialize_header(headers::Vector{Pair{String, String}})
    buf = IOBuffer()
    write(buf, "NATS/1.0\r\n")
    for (key, value) in headers
        write(buf, key)
        write(buf, ": ")
        write(buf, value)
        write(buf, "\r\n")
    end
    return String(take!(buf))
end

function deserialize_header(header_str::AbstractString)
    hdr = split(header_str, "\r\n"; keepempty = false)
    @assert first(hdr) == "NATS/1.0"
    items = hdr[2:end]
    items = split.(items, ": "; keepempty = false)
    map(x -> string(first(x)) => string(last(x)) , items)
end