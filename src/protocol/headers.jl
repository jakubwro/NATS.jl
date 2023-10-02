# Headers parsig and serializing. Headers are represented as vector of paris of strings.

const Header = Pair{String, String}
const Headers = Vector{Header}

function headers(msg::Msg)
    Headers()
end

function headers(hmsg::HMsg)
    hdr = split(hmsg.headers, "\r\n"; keepempty = false)
    @assert startswith(first(hdr), "NATS/1.0") "Missing protocol version."
    items = hdr[2:end]
    items = split.(items, ": "; keepempty = false)
    map(x -> string(first(x)) => string(last(x)) , items)
end

function headers(m::Union{Msg,HMsg}, key::String)
    last.(filter(h -> first(h) == key, headers(m)))
end

function header(m::Union{Msg,HMsg}, key::String)
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

function statuscode(::Msg)
    200
end

function statuscode(hmsg::HMsg)
    statuscode(hmsg.headers)
end