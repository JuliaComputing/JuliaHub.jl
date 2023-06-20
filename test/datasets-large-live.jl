@info "Uploading test data with prefix: JuliaHubLargeTest_$(TESTID)"
dataset_name = "JuliaHubLargeTest_$(TESTID)_Blob"
try
    open("testdata/large.dat", "w") do io
        chunk = ones(UInt8, 1024^2)
        # 210 MB forces multipart upload in rclone
        for i = 1:210
            write(io, chunk)
        end
    end
    JuliaHub.upload_dataset(dataset_name,
        "testdata/large.dat";
        description="some blob", tags=["x", "y", "z"],
        auth)
    datasets = JuliaHub.datasets(; auth)
    blob_dataset = only(filter(d -> d.name == dataset_name, datasets))
    @test blob_dataset.size == filesize("testdata/large.dat")
finally
    try
        JuliaHub.delete_dataset(dataset_name; auth)
    catch err
        @warn "Failed to delete dataset '$(dataset_name)'" exception = (err, catch_backtrace())
    end
end
