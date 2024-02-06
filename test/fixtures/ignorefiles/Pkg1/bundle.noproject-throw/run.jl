using Pkg1

@assert Pkg1.whoami() == "pkg1"
@assert Pkg1.Pkg2.whoami() == "pkg2"
@assert Pkg1.Pkg3.whoami() == "pkg3"

for i in 1:100
    println(i)
    sleep(1)
end
