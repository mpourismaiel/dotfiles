async.dag(
    {
        get_data = { function(cb)
            local f = fs.open("/tmp/foo.txt")
            f:read(cb)
        end },
        make_folder = { function(cb)
            fs.make_folder("/tmp/bar", cb)
        end },
        write_data = { "get_data", "make_folder", function(results, cb)
            local data = table.unpack(results.get_data)
            local f = fs.open("/tmp/bar/foo.txt")
            f:write(data, cb)
        end },
    },
    function(err, results)
        if err ~= nil then
            error(err)
        else
            print("success")
        end
    end
)
