{ config, pkgs, lib, ... }:
let
    kernel = config.hardware.sc0710.kernel;
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
      
          make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
          M=$PWD/build \
          ${lib.escapeShellArgs (kernel.commonMakeFlags or [ ])} \
          INSTALL_MOD_PATH=$out \
          modules_install

          rm -f $out/lib/modules/${kernel.modDirVersion}/modules.*

          find $out -name 'sc0710.ko.cer' | grep -q . \
          || { echo "sc0710.ko.cer was not produced"; exit 1; }

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
