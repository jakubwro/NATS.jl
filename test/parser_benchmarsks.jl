
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
    @time NATS.parser_loop(io) do res
        @info "res" first(res)
    end
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