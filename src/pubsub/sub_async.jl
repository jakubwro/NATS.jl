
function _start_async_handler(f::Function, subject::String)
    error_ch = Channel(100000)

    ch = Channel(10000000, spawn = true) do ch # TODO: move to const
        try
            while true
                msg = take!(ch)
                Threads.@spawn :default try
                    f(msg)
                catch err
                    put!(error_ch, err)
                end
            end
        catch
            close(error_ch)
        end
    end
    Threads.@spawn :default begin
        while true
            sleep(5)
            avail = Base.n_avail(error_ch)
            errors = [ take!(error_ch) for _ in 1:avail ]
            if !isempty(errors)
                @error "$(length(errors)) handler errors on \"$subject\" in last 5 s. Last one:" last(errors)
            end
        end
    end
    ch
end
