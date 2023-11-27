# Headers parsig and serializing. Headers are represented as vector of paris of strings.

const Header = Pair{String, String}
const Headers = Vector{Header}

function headers_str(msg::Msg)
    String(msg.payload[begin:msg.headers_length])
end

function headers(msg::Msg)
    if msg.headers_length == 0
        return Headers()
    end
    hdr = split(headers_str(msg), "\r\n"; keepempty = false)
    @assert startswith(first(hdr), "NATS/1.0") "Missing protocol version."
    items = hdr[2:end]
    items = split.(items, ": "; keepempty = false)
    map(x -> string(first(x)) => string(last(x)) , items)
end

function headers(m::Msg, key::String)
    last.(filter(h -> first(h) == key, headers(m)))
end

function header(m::Msg, key::String)
    only(headers(m, key))
end

function statuscode(header_str::String)
    hdr = split(header_str, "\r\n"; keepempty = false, limit = 2)
    if ' ' in first(hdr)
        version, status = split(first(hdr), ' ')
        parse(Int, status)
    else
        200
    end
end

function statuscode(msg::Msg)
    if msg.headers_length == 0
        200
    else
        statuscode(headers_str(msg))
    end
end
