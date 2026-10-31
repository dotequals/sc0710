{ config, pkgs, lib, ... }:
let
    minimumKernel = "6.12";
    currentKernelMajorMinor = lib.versions.majorMinor config.hardware.sc0710.kernel.version;

    package-version = lib.fileContents ./version;

    cli = pkgs.writeShellScriptBin "sc0710-cli" (builtins.readFile ./scripts/sc0710-cli.sh);

    driver = pkgs.stdenv.mkDerivation rec {
        name = "sc0710-${package-version}-${config.hardware.sc0710.kernel.version}";
        version = package-version;

        enableParallelBuilding = true;

        src = ./.;
        nativeBuildInputs = config.hardware.sc0710.kernel.moduleBuildDependencies;

        makeFlags = [
            "KBUILD_DIR=${config.hardware.sc0710.kernel.dev}/lib/modules/${config.hardware.sc0710.kernel.modDirVersion}/build"
        ];

        # fixupPhase's strip would run after signing and invalidate the signature,
        # so we strip manually in installPhase, before signing.
        dontStrip = true;
      
        installPhase = ''
          runHook preInstall
      
          dir=$out/lib/modules/${config.hardware.sc0710.kernel.modDirVersion}/kernel/drivers/media/pci
          mkdir -p $dir
          install -m644 build/sc0710.ko $dir/sc0710.ko
      
          # nixpkgs now expects a signed module plus a sc0710.ko.cer next to it.
          # Strip first, then sign (signing before stripping leaves it unsigned).
          strip --strip-debug $dir/sc0710.ko
          kmodigest $dir/sc0710.ko
      
          runHook postInstall
        '';
    };
in
{
    options = {
        hardware.sc0710 = {
            enable = lib.mkEnableOption "Enable the sc0710 kernel module";
            kernel = lib.mkOption {
                default = config.boot.kernelPackages.kernel;
            };
        };
    };
    config = (lib.mkIf (config.hardware.sc0710.enable) {
        assertions = [
            {
                assertion = lib.versionAtLeast currentKernelMajorMinor minimumKernel;
                message = "sc0710 driver is not compatible with kernel ${currentKernelMajorMinor}. It requires at least version ${minimumKernel}.";
            }
        ];

        boot.extraModulePackages   = [ driver   ];
        boot.kernelModules         = [ "sc0710" ];
        environment.systemPackages = [ cli      ];

        # ECP5-based cards: the driver programs the FPGA during probe and needs
        # card-specific firmware on disk; provision it with scripts/extract-firmware.sh
        # (installs to /lib/firmware/sc0710, which the kernel loader reads directly).
    });
}
