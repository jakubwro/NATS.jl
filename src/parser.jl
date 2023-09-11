CRLF = "\r\n"
SEPARATOR = ' '
DISPATCH_PROTOCOL_MESSAGE = Dict(
    "INFO" => Info,
    "PING" => Ping,
    "PONG" => Pong,
    "MSG"  => Msg,
    "HMSG" => HMsg,
    "+OK"  => Ok,
    "-ERR" => Err
)

function next_protocol_message(io::IO)::ProtocolMessage
    headline = readuntil(io, CRLF)
    isempty(headline) && error("Empty message.")
    op = first(split(headline, SEPARATOR; keepempty=false, limit=2))
    isempty(op) && error("Received empty line.")
    type = get(DISPATCH_PROTOCOL_MESSAGE, op, nothing)
    isnothing(type) && error("Unexpected protocol message: '$op'")
    next_protocol_message(type, headline, io)
end

function next_protocol_message(::Type{Info}, headline::String, io::IO)::Info
    json = SubString(headline, length("INFO "))
    JSON3.read(json, Info)
end

function next_protocol_message(::Type{Msg}, headline::String, io::IO)::Msg
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, nbytes) = 
        if length(args) == 4
            nothing, parse(Int64, args[4])
        else
            args[4], parse(Int64, args[5])
        end
    bytes = read(io, nbytes)
    readuntil(io, CRLF)
    payload = String(bytes)
    @assert ncodeunits(payload) == nbytes "Unexpected payload length."
    return Msg(subject, sid, replyto, nbytes, payload)
end

function next_protocol_message(::Type{HMsg}, headline::String, io::IO)::HMsg
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, hbytes, nbytes) = 
        if length(args) == 5
            nothing, parse(Int64, args[4]), parse(Int64, args[5])
        else
            args[4], parse(Int64, args[5]), parse(Int64, args[6])
        end
    bytes = read(io, hbytes)
    headers = String(bytes)
    ncodeunits(headers) == hbytes || error("Wrong headers length.")
    bytes = read(io, nbytes - hbytes)
    payload = String(bytes)
    ncodeunits(payload) == nbytes - hbytes || error("Wrong payload length.")
    return HMsg(subject, sid, replyto, hbytes, nbytes, headers, payload)
end

function next_protocol_message(::Type{Ok}, headline::String, io::IO)::Ok
    Ok()
end

function next_protocol_message(::Type{Err}, headline::String, io::IO)::Err
    left = length("-ERR '") + 1
    right = length(headline) - length("'")
    Err(headline[left:right])
end

function next_protocol_message(::Type{Ping}, headline::String, io::IO)::Ping
    Ping()
end

function next_protocol_message(::Type{Pong}, headline::String, io::IO)::Pong
    Pong()
end
