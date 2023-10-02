# Read next protocol message from input stream.

const CRLF = "\r\n"
const SEPARATOR = ' '

function next_protocol_message(io::IO)::ProtocolMessage
    headline = readuntil(io, CRLF)
    if     startswith(headline, "MSG")  parse_msg(headline, io)
    elseif startswith(headline, "HMSG") parse_hmsg(headline, io)
    elseif startswith(headline, "+OK")  Ok()
    elseif startswith(headline, "PING") Ping()
    elseif startswith(headline, "PONG") Pong()
    elseif startswith(headline, "-ERR") parse_err(headline)
    elseif startswith(headline, "INFO") parse_info(headline)
    else                                error("Unexpected protocol message: '$headline'.")
    end
end

function parse_info(headline::String)::Info
    json = SubString(headline, length("INFO "))
    JSON3.read(json, Info)
end

function parse_msg(headline::String, io::IO)::Msg
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, nbytes) = 
        if length(args) == 4
            nothing, parse(Int64, args[4])
        else
            args[4], parse(Int64, args[5])
        end
    bytes = read(io, nbytes)
    read(io, length(CRLF))
    payload = String(bytes)
    @assert sizeof(payload) == nbytes "Unexpected payload length."
    Msg(subject, sid, replyto, nbytes, payload)
end

function parse_hmsg(headline::String, io::IO)::HMsg
    args = split(headline, SEPARATOR; keepempty=false)
    (subject, sid) = args[2:3]
    (replyto, hbytes, nbytes) = 
        if length(args) == 5
            nothing, parse(Int64, args[4]), parse(Int64, args[5])
        else
            args[4], parse(Int64, args[5]), parse(Int64, args[6])
        end
    headers = hbytes == 0 ? nothing : String(read(io, hbytes))
    sizeof(headers) == hbytes || error("Wrong headers length.")
    payload = hbytes == nbytes ? nothing : String(read(io, nbytes - hbytes))
    sizeof(payload) == nbytes - hbytes || error("Wrong payload length.")
    read(io, length(CRLF))
    HMsg(subject, sid, replyto, hbytes, nbytes, headers, payload)
end

function parse_err(headline::String)::Err
    left = length("-ERR '") + 1
    right = length(headline) - length("'")
    Err(headline[left:right])
end
