import StructTypes: omitempties

StructTypes.omitempties(::Type{Connect}) = true

function serialize(connect::Connect)
    "CONNECT $(JSON3.write(connect))\r\n"
end

function serialize(pub::Pub)
    payload = isnothing(pub.payload) ? "" : pub.payload
    nbytes = ncodeunits(payload)
    reply_to = isnothing(pub.reply_to) ? "" : " $(pub.reply_to)"
    "PUB $(pub.subject)$reply_to $nbytes\r\n$(payload)\r\n"
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
