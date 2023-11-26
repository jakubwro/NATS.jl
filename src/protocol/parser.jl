# Read next protocol message from input stream.

const CRLF = "\r\n"
const SEPARATOR = ' '

function next_protocol_message(io::IO)::ProtocolMessage
    headline = readuntil(io, CRLF)
    if     startswith(headline, "+OK")  Ok()
    elseif startswith(headline, "PING") Ping()
    elseif startswith(headline, "PONG") Pong()
    elseif startswith(headline, "-ERR") parse_err(headline)
    elseif startswith(headline, "INFO") parse_info(headline)
    elseif startswith(headline, "MSG")  error("Parsing MSG not supported")
    elseif startswith(headline, "HMSG") error("Parsing HMSG not supported")
    else                                error("Unexpected protocol message: '$headline'.")
    end
end

function parse_info(headline::String)::Info
    json = SubString(headline, length("INFO "))
    JSON3.read(json, Info)
end

function parse_err(headline::String)::Err
    left = length("-ERR '") + 1
    right = length(headline) - length("'")
    Err(headline[left:right])
end
