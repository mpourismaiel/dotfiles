{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-22.11";

  outputs = { self, nixpkgs }:
    let
      flakePkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ self.overlays.default ];
      };

      currentVersion = builtins.readFile ./VERSION;

      buildPackage = pname: luaPackages: with luaPackages;
        buildLuaPackage rec {
          name = "${pname}-${version}";
          inherit pname;
          version = "${currentVersion}-${self.shortRev or "dev"}";

          src = ./.;

          propagatedBuildInputs = [ lua lgi ];

          buildInputs = [ busted luacov ldoc luacheck ];

          buildPhase = ":";

          installPhase = ''
            mkdir -p "$out/share/lua/${lua.luaversion}"
            cp -r src/${pname} "$out/share/lua/${lua.luaversion}/"
          '';

          doCheck = true; # more tests done using the flake checks
          checkPhase = "luacheck src tests";

        };

      makeCheck = lua: luaPackages: flakePkgs.nixosTest {
        name = luaPackages.dbus_proxy.name;
        nodes.machine = { pkgs, lib, ... }: {

          virtualisation.writableStore = true;
          nix.settings.substituters = lib.mkForce [ ]; # no network

          nixpkgs.overlays = [

            self.overlays.default

            (this: super: {

              dbus_proxy_tests = pkgs.stdenv.mkDerivation {
                name = "dbus_proxy_tests";
                src = ./.;
                buildPhase = ":";
                installPhase = "mkdir -p $out/tests && cp -r tests/ $out/tests/";
                doCheck = false;
              };

              dbus_proxy_app = lua.withPackages (ps: [
                luaPackages.dbus_proxy
              ] ++ luaPackages.dbus_proxy.buildInputs);
            })

          ];

          environment.variables = {
            LUA_DBUS_PROXY_TESTS_PATH = "${pkgs.dbus_proxy_tests}";
          };

          users.users.test-user = {
            isNormalUser = true;
            shell = pkgs.bashInteractive;
            password = "just-A-pass";
            home = "/home/test-user";
            packages = [ pkgs.dbus_proxy_app ];
          };

        };

        testScript = ''
          # To use DBus properly, login and execute the test suite.
          # strategy taken from nixos/tests/login.nix
          machine.wait_for_unit("multi-user.target")
          machine.wait_until_tty_matches("1", "login: ")
          machine.send_chars("test-user\n")
          machine.wait_until_tty_matches("1", "login: test-user")
          machine.wait_until_succeeds("pgrep login")
          machine.wait_until_tty_matches("1", "Password: ")
          machine.send_chars("just-A-pass\n")
          machine.wait_until_succeeds("pgrep -u test-user bash")
          machine.send_chars("busted $LUA_DBUS_PROXY_TESTS_PATH > output\n")
          machine.wait_for_file("/home/test-user/output")
          machine.send_chars("echo $? > result\n")
          machine.wait_for_file("/home/test-user/result")
          output = machine.succeed("cat /home/test-user/output")
          result = machine.succeed("cat /home/test-user/result")
          assert result == "0\n", "Test suite failed: {}".format(output)
          print(output)
        '';

      };

    in
    {
      packages.x86_64-linux = rec {
        default = lua_dbus_proxy;
        lua_dbus_proxy = buildPackage "dbus_proxy" flakePkgs.luaPackages;
        lua52_dbus_proxy = buildPackage "dbus_proxy" flakePkgs.lua52Packages;
        lua53_dbus_proxy = buildPackage "dbus_proxy" flakePkgs.lua53Packages;
        luajit_dbus_proxy = buildPackage "dbus_proxy" flakePkgs.luajitPackages;
      };

      overlays.default = final: prev: with self.packages.x86_64-linux; {
        # NOTE: lua = prev.lua.override { packageOverrides = this: other: {... }}
        # Seems to be broken as it does not allow to combine different overlays.

        luaPackages = prev.luaPackages // {
          dbus_proxy = lua_dbus_proxy;
        };

        # Lua 5.1 is does not work
        # lua51Packages = prev.lua51Packages // {
        #   dbus_proxy = lua51_dbus_proxy;
        # };

        lua52Packages = prev.lua52Packages // {
          dbus_proxy = lua52_dbus_proxy;
        };

        lua53Packages = prev.lua53Packages // {
          dbus_proxy = lua53_dbus_proxy;
        };

        luajitPackages = prev.luajitPackages // {
          dbus_proxy = luajit_dbus_proxy;
        };

      };

      devShells.x86_64-linux.default = flakePkgs.mkShell {
        LUA_PATH = "./src/?.lua;./src/?/init.lua";
        buildInputs = (with self.packages.x86_64-linux.default; buildInputs ++ propagatedBuildInputs) ++ (with flakePkgs; [
          nixpkgs-fmt
          luarocks
        ]);
      };

      checks.x86_64-linux = {
        lua52Check = with flakePkgs; makeCheck lua5_2 lua52Packages;
        lua53Check = with flakePkgs; makeCheck lua5_3 lua53Packages;
        luajitCheck = with flakePkgs; makeCheck luajit luajitPackages;
      } // self.packages.x86_64-linux;

    };
}
