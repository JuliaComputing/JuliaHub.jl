@info "Uploading test data with prefix: JuliaHubLargeTest_$(TESTID)"
dataset_name = "JuliaHubLargeTest_$(TESTID)_Blob"
large_data_file = joinpath(TESTDATA, "large.dat")
try
    lf_ds, lf_filesize = mktemp() do path, io
        chunk = ones(UInt8, 1024^2)
        # 210 MB forces multipart upload in rclone
        for i = 1:210
            write(io, chunk)
        end
        close(io)
        # Upload the file
        r = JuliaHub.upload_dataset(
            dataset_name, path;
            description="some blob", tags=["x", "y", "z"],
            auth
        )
        r, filesize(path)
    end
    @test lf_ds isa JuliaHub.Dataset
    @test lf_ds.name == dataset_name

    datasets = JuliaHub.datasets(; auth)
    blob_dataset = only(filter(d -> d.name == dataset_name, datasets))
    @test blob_dataset.size == lf_filesize
finally
    try
        JuliaHub.delete_dataset(dataset_name; auth)
    catch err
        @warn "Failed to delete dataset '$(dataset_name)'" exception = (err, catch_backtrace())
    end
    # Also clean up the
    rm(large_data_file; force=true)
end
