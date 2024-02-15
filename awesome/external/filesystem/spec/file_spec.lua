local assert = require("luassert")
local spy = require("luassert.spy")
local async = require("async")

local lgi = require("lgi")
local GLib = lgi.GLib
local Gio = lgi.Gio
local File = require("lgi-async-extra.file")

local function run_file(fn)
    return run(function(cb)
        local f = File.new_tmp()
        fn(f, function(err)
            f:delete(function(err_inner)
                cb(err or err_inner)
            end)
        end)
    end)
end

describe('file', function()
    describe('is_instance', function()
        it('returns true for Files', function()
            assert(File.is_instance(File.new_for_path("/tmp/foo.txt")))
        end)

        it('returns false for strings', function()
            assert(not File.is_instance(""))
            assert(not File.is_instance("/tmp/foo.txt"))
        end)

        it('returns false for tables', function()
            assert(not File.is_instance({}))
            assert(not File.is_instance({ foo = "bar", "baz" }))
        end)

        it('returns false for numbers', function()
            assert(not File.is_instance(1))
            assert(not File.is_instance(100))
        end)

        it('returns false for userdata', function()
            assert(not File.is_instance(lgi.Gio.File.new_for_path("/tmp/foo.txt")))
            assert(not File.is_instance(lgi.GLib.Bytes.new()))
        end)
    end)

    describe('exists', function()
        it('returns false for non-existent file', run(function(cb)
            local f = File.new_for_path("/this_should_not.exist")

            f:exists(function(err, exists)
                wrap_asserts(cb, err, function()
                    assert.is_false(exists)
                    assert.is_function(cb)
                end)
            end)
        end))

        it('handles file deletion', run(function(cb)
            local f = File.new_tmp()

            local check_exists = spy(function(exists, cb)
                wrap_asserts(cb, function()
                    assert.is_true(exists)
                    assert.is_function(cb)
                end)
            end)

            local check_removed = spy(function(exists, cb)
                wrap_asserts(cb, function()
                    assert.is_false(exists)
                    assert.is_function(cb)
                end)
            end)

            async.waterfall({
                async.callback(f, f.exists),
                check_exists,
                async.callback(f, f.delete),
                async.callback(f, f.exists),
                check_removed,
            }, function(err)
                wrap_asserts(cb, err, function()
                    assert.spy(check_exists).was_called()
                    assert.spy(check_removed).was_called()
                end)
            end)
        end))
    end)

    it('writes and reads', run_file(function(f, cb)
        local str = "Hello, World!"

        local check_read_empty = spy(function(cb)
            wrap_asserts(cb, function()
                assert.is_function(cb)
            end)
        end)

        local check_read_data = spy(function(data, cb)
            wrap_asserts(cb, function()
                assert.is_same(str, data)
                assert.is_function(cb)
            end)
        end)

        async.waterfall({
            async.callback(f, f.read_string),
            check_read_empty,
            async.callback(f, f.write, str, "replace"),
            async.callback(f, f.read_string),
            check_read_data,
        }, function(err)
            wrap_asserts(cb, err, function()
                assert.spy(check_read_empty).was_called()
                assert.spy(check_read_data).was_called()
            end)
        end)
    end))

    describe('read_bytes', function()
        it('returns empty bytes for empty file', run_file(function(f, cb)
            f:read_bytes(4096, function(err, bytes)
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.is_userdata(bytes)
                    assert.is_same(0, #bytes)
                end)
            end)
        end))

        it('reads the specified number of bytes, if possible', run_file(function(f, cb)
            local data = "Hello, world!"

            async.waterfall({
                async.callback(f, f.write, data, "replace"),
                function(cb)
                    f:read_bytes(#data, function(err, bytes)
                        wrap_asserts(cb, err, function()
                            assert.is_nil(err)
                            assert.is_userdata(bytes)
                            assert.is_same(#data, #bytes)
                            assert.is_same(data, bytes:get_data())
                        end)
                    end)
                end,
            }, cb)
        end))

        it('reads less if not enough data', run_file(function(f, cb)
            local BUFFER_SIZE = 4096
            local data = "Hello, world!"

            async.waterfall({
                async.callback(f, f.write, data, "replace"),
                function(cb)
                    f:read_bytes(BUFFER_SIZE, function(err, bytes)
                        wrap_asserts(cb, err, function()
                            assert.is_nil(err)
                            assert.is_userdata(bytes)
                            assert(#bytes < BUFFER_SIZE)
                            assert.is_same(#data, #bytes)
                            assert.is_same(data, bytes:get_data())
                        end)
                    end)
                end,
            }, cb)
        end))

        it('reads binary data', run(function(cb)
            local f = File.new_for_path("/dev/random")
            local BUFFER_SIZE = 100

            f:read_bytes(BUFFER_SIZE, function(err, bytes)
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.is_userdata(bytes)
                    assert.is_same(BUFFER_SIZE, #bytes)
                    assert.is_string(bytes:get_data())
                end)
            end)
        end))
    end)

    describe('read_string', function()
        it('returns nil for empty file', run_file(function(f, cb)
            f:read_string(function(err, str)
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.is_nil(str)
                end)
            end)
        end))

        it('reads a short file, less than buffer size', run_file(function(f, cb)
            local data = "Hello, world!"

            async.waterfall({
                async.callback(f, f.write, data, "replace"),
                function(cb)
                    f:read_string(function(err, str)
                        wrap_asserts(cb, err, function()
                            assert.is_nil(err)
                            assert.is_string(str)
                            assert.is_same(data, str)
                        end)
                    end)
                end,
            }, cb)
        end))

        it('reads a long file', run_file(function(f, cb)
            local data = {}
            for _ = 1, 1000 do
                table.insert(data, "Hello, world!")
            end
            data = table.concat(data, "\n")

            async.waterfall({
                async.callback(f, f.write, data, "replace"),
                function(cb)
                    f:read_string(function(err, str)
                        wrap_asserts(cb, err, function()
                            assert.is_nil(err)
                            assert.is_string(str)
                            assert.is_same(data, str)
                        end)
                    end)
                end,
            }, cb)
        end))

        it('reads virtual files', run(function(cb)
            local f = File.new_for_path("/proc/meminfo")

            local check_read_string = spy(function(data, cb)
                wrap_asserts(cb, function()
                    assert.is_string(data)
                    assert.is_not_nil(data:match("SwapTotal"))
                end)
            end)

            async.waterfall({
                async.callback(f, f.read_string),
                check_read_string,
            }, function(err)
                wrap_asserts(cb, err, function()
                    assert.spy(check_read_string).was_called()
                end)
            end)
        end))
    end)

    describe('read_line', function()
        it('returns nil for empty file', run_file(function(f, cb)
            f:read_line(function(err, line)
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.is_nil(line)
                end)
            end)
        end))

        it('always reads the first line', run_file(function(f, cb)
            local lines = { "Hello, World!", "Second Line" }

            local check_line = spy(function(data, cb)
                wrap_asserts(cb, function()
                    assert.is_same(lines[1], data)
                    assert.is_function(cb)
                end)
            end)

            async.waterfall({
                async.callback(f, f.write, table.concat(lines, "\n"), "replace"),
                async.callback(f, f.read_line),
                check_line,
                async.callback(f, f.read_line),
                check_line,
            }, function(err)
                wrap_asserts(cb, err, function()
                    assert.spy(check_line).was_called(2)
                end)
            end)
        end))

        it('reads virtual files', run(function(cb)
            local f = File.new_for_path("/proc/meminfo")

            f:read_line(function(err, line)
                wrap_asserts(cb, err, function()
                    assert.is_string(line)
                    assert.is_same("MemTotal", line:match("MemTotal"))
                end)
            end)
        end))
    end)

    describe('iterate_lines', function()
        it('iterates over lines', run_file(function(f, cb)
            local lines = { "Hello, World!", "Second Line" }
            local count = 1

            local check_line = spy(function(err, line, cb)
                if type(line) == "function" then
                    cb = line
                    line = nil
                end

                wrap_asserts(cb, err, function()
                    if count > 2 then
                        assert.is_nil(line)
                    else
                        assert.is_same(lines[count], line)
                    end
                    assert.is_function(cb)
                    count = count + 1
                end)
            end)

            async.waterfall({
                async.callback(f, f.write, table.concat(lines, "\n"), "replace"),
                function(cb)
                    f:iterate_lines(check_line, cb)
                end,
            }, function(err)
                wrap_asserts(cb, err, function()
                    assert.spy(check_line).was_called(3)
                end)
            end)
        end))
    end)

    describe('delete', function()
        it('does not delete directory with content', run(function(cb)
            local dir = string.format("%s/lgi-async-extra_tests_delete", GLib.get_tmp_dir())
            os.execute(string.format('mkdir %s', dir))
            os.execute(string.format('bash -c "touch %s/{1,2,3}"', dir))

            local f = File.new_for_path(dir)
            f:delete(function(err)
                os.execute(string.format("rm -r %s", dir))
                wrap_asserts(cb, function()
                    assert.is_not_nil(err)
                    assert.is_same(Gio.IOErrorEnum, err.domain)
                    assert.is_same(Gio.IOErrorEnum.NOT_EMPTY, Gio.IOErrorEnum[err.code])
                end)
            end)
        end))
    end)

    describe('create', function()
        it('creates the file', run(function(cb)
            local path = string.format("%s/lgi-async-extra_tests_create", GLib.get_tmp_dir())
            local f = File.new_for_path(path)

            local check_exists = spy(function(exists, cb)
                wrap_asserts(cb, function()
                    assert.is_true(exists)
                    assert.is_function(cb)
                end)
            end)

            async.waterfall({
                async.callback(f, f.create),
                async.callback(f, f.exists),
                check_exists,
            }, function(err)
                os.execute(string.format("rm %s", path))
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.spy(check_exists).was_called()
                end)
            end)
        end))

        it('fails when the file exists', run(function(cb)
            local path = string.format("%s/lgi-async-extra_tests_create", GLib.get_tmp_dir())
            local f = File.new_for_path(path)

            os.execute(string.format("touch %s", path))

            f:create(function(err)
                os.execute(string.format("rm %s", path))
                wrap_asserts(cb, function()
                    assert.is_not_nil(err)
                    assert.is_same(Gio.IOErrorEnum, err.domain)
                    assert.is_same(Gio.IOErrorEnum.EXISTS, Gio.IOErrorEnum[err.code])
                end)
            end)
        end))
    end)

    describe('copy', function()
        it('copies regular file', run_file(function(f, cb)
            local path = string.format("%s/lgi-async-extra_tests_copy", GLib.get_tmp_dir())

            local check_exists = spy(function(exists, cb)
                wrap_asserts(cb, function()
                    assert.is_true(exists)
                    assert.is_function(cb)
                end)
            end)

            async.waterfall({
                function(cb)
                    f:copy(path, {}, cb)
                end,
                async.callback(f, f.exists),
                check_exists,
            }, function(err)
                os.execute(string.format("rm %s", path))
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.spy(check_exists).was_called()
                end)
            end)
        end))

        it('copies a symlink', run(function(cb)
            local path = string.format("%s/lgi-async-extra_tests_copy", GLib.get_tmp_dir())
            local dest_path = string.format("%s/lgi-async-extra_tests_copy_dest", GLib.get_tmp_dir())
            local f = File.new_for_path(path)
            os.execute(string.format("ln -s foo %s", path))

            local data = "Hello, world!"

            local check_exists = spy(function(exists, cb)
                wrap_asserts(cb, function()
                    assert.is_true(exists)
                    assert.is_function(cb)
                end)
            end)

            async.waterfall({
                function(cb)
                    f:write(data, cb)
                end,
                function(cb)
                    f:copy(dest_path, {}, cb)
                end,
                function(cb)
                    f:exists(cb)
                end,
                check_exists,
                function(cb)
                    File.new_for_path(dest_path):exists(cb)
                end,
                check_exists,
            }, function(err)
                os.execute(string.format("rm %s %s", path, dest_path))
                wrap_asserts(cb, err, function()
                    assert.is_nil(err)
                    assert.spy(check_exists).was_called(2)
                end)
            end)
        end))
    end)
end)
