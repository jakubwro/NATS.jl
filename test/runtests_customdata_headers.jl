
using Test
using NATS

import Base: convert, show

struct Person
    name::String
    age::Int64
    departament::String
end

function convert(::Type{Person}, msg::NATS.Msg)
    name, age, departament = split(payload(msg), ",")
    Person(name, parse(Int64, age), departament)
end

function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
    print(io, ",")
    print(io, person.departament)
end

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection."
nc = NATS.connect(default = true)

@testset "Publish subscribe with custom data" begin
    c = Channel()
    sub = subscribe("EMPLOYEES") do person::Person
        put!(c, person)
    end
    publish("EMPLOYEES", Person("Jacek", 33, "IT"))
    result = take!(c)
    @test result isa Person
    @test result.name == "Jacek"
    @test result.age == 33
    @test length(NATS.state.handlers) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(NATS.state.handlers) == 0
end

@testset "Request reply with custom data" begin
    sub = reply("EMPLOYEES.SUPERVISOR") do person::Person
        if person.departament == "IT"
            Person("Zbigniew", 44, "IT"), ["status" => "ok"]
        elseif person.departament == "HR"
            Person("Maciej", 55, "HR"), ["status" => "ok"]
        else
            @info "Error response."
            ["status" => "error", "message" => "Unexpected departament `$(person.departament)`"]
        end
    end
    supervisor = request(Person, "EMPLOYEES.SUPERVISOR", Person("Jacek", 33, "IT"))
    @test supervisor isa Person
    @test supervisor.name == "Zbigniew"
    @test supervisor.age == 44

    msg = request("EMPLOYEES.SUPERVISOR", Person("Anna", 33, "ACCOUNTING"))
    @test msg isa NATS.Msg
    @test headers(msg) == ["status" => "error", "message" => "Unexpected departament `ACCOUNTING`"]
    unsubscribe(sub)
end