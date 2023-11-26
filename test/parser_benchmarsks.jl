
msg = "MSG foo 84s6LXpSRziIFL4w5Spm 16\r\n1111111111111111\r\n"
io = IOBuffer(repeat(msg, 10000))

@time for b in readavailable(io)

end

using NATS

res = NATS.parser_loop(io) do res
    @info length(res)
end

function bench_parser()
    msg = "MSG foo 84s6LXpSRziIFL4w5Spm 16\r\n1111111111111111\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    ret = []
    @time NATS.parser_loop(io) do res
        ret = res
        # @info "res" first(res) length(res)
    end
    ret
end

function bench_parser_replyto()
    msg = "MSG foo 84s6LXpSRziIFL4w5Spm asdf 16\r\n1111111111111111\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    ret = []
    @time NATS.parser_loop(io) do res
        ret = res
        @info "res" first(res) length(res)
    end
    ret
end

function bench_parser_headers()
    msg = "HMSG FOO.BAR 9 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    @time NATS.parser_loop(io) do res
        @info "res" first(res) length(res)
    end
end

function bench_parser_headers_replyto()
    msg = "HMSG FOO.BAR 9 asdf 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    ret = []
    @time NATS.parser_loop(io) do res
        ret = res
        @info "res" first(res) length(res)
    end
    ret
end

function bench()
    msg = "MSG foo 84s6LXpSRziIFL4w5Spm 16\r\n1111111111111111\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    @time for b in readavailable(io)
        if s < 10000
            if b == 0x44
                s += 2
            elseif b == 0x45
                s += 5
            elseif b == 0x48
                s -= 1
            elseif b == 0x49
                s += 9
            elseif b == 0x40
                s -= 5
            end
        else
            s+= 100
        end
    end    
end

using StringViews
function scan()
    msg = "MSG foo 84s6LXpSRziIFL4w5Spm 16\r\n1111111111111111\r\n"
    io = IOBuffer(repeat(msg, 1000000))
    s = 0
    m = false
    cr = false
    crlf = false
    in_payload = false
    pos = 0
    ends = sizehint!(Int64[], 2000000)
    subs = sizehint!(AbstractString[], 2000000)
    @time buffer = readavailable(io)
    msgs = []
    last_end = 0
    @time for b in buffer
        pos += 1
        crlf = false
        if b == convert(UInt8, '\r')
            cr = true
        elseif cr && b == convert(UInt8, '\n')
            crlf = true
            cr = false
        elseif b == convert(UInt8, 'M')
            m = true
        end

        if !m && crlf
            push!(msgs, NATS.Msg("foo", String(StringView(@view buffer[last_end+1:pos])), "", 16, "1111111111111111"))
            # push!(msgs, SubString(StringView(@view buffer[last_end+1:pos]), 9, 29))
            # push!(msgs, SubString(StringView(@view buffer[last_end+1:pos]), 9, 29))
            last_end = pos
        elseif crlf
            m = false
        end
    end
    msgs
end