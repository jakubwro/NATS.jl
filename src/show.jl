import StructTypes: omitempties

StructTypes.omitempties(::Type{Connect}) = true

function show(io::IO, ::MIME"application/nats", connect::Connect)
    write(io, "CONNECT $(JSON3.write(connect))\r\n")
end

function show(io::IO, ::MIME"application/nats", pub::Pub)
    payload = isnothing(pub.payload) ? "" : pub.payload
    nbytes = sizeof(payload)
    reply_to = isnothing(pub.reply_to) ? "" : " $(pub.reply_to)"
    write(io, "PUB $(pub.subject)$reply_to $nbytes\r\n$(payload)\r\n")
end

function show(io::IO, ::MIME"application/nats", hpub::HPub)
    hbytes = sizeof(hpub.headers)
    pbytes = sizeof(hpub.payload)
    nbytes = pbytes + hbytes
    reply_to = isnothing(hpub.reply_to) ? "" : " $(hpub.reply_to)"
    write(io, "HPUB $(hpub.subject)$reply_to $hbytes $nbytes\r\n$(hpub.headers)$(hpub.payload)\r\n")
end

function show(io::IO, ::MIME"application/nats", sub::Sub)
    queue_group = isnothing(sub.queue_group) ? "" : " $(sub.queue_group)"
    write(io, "SUB $(sub.subject)$queue_group $(sub.sid)\r\n")
end

function show(io::IO, ::MIME"application/nats", unsub::Unsub)
    max_msgs = isnothing(unsub.max_msgs) ? "" : " $(unsub.max_msgs)"
    write(io, "UNSUB $(unsub.sid)$max_msgs\r\n")
end

function show(io::IO, ::MIME"application/nats", unsub::Ping) 
    write(io, "PING\r\n")
end

function show(io::IO, ::MIME"application/nats", unsub::Pong)
    write(io, "PONG\r\n")
end

function show(io::IO, ::MIME"application/nats", headers::Headers)
    print(io, "NATS/1.0\r\n")
    for (key, value) in headers
        print(io, key)
        print(io, ": ")
        print(io, value)
        print(io, "\r\n")
    end
    print(io, "\r\n")
end
