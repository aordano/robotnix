{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf mkMerge mkDefault;

  # TODO modularize in a config file
  postRedfin = lib.elem config.deviceFamily [ "redfin" "barbet" "raviole" "bluejay" "pantah" ];
  postRaviole = lib.elem config.deviceFamily [ "raviole" "bluejay" "pantah" ];

  # Gotten from https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/master/README.md
  # TODO modularize in a config file
  clangVersion = "${
    lib.optionalString (config.androidVersion == 14) "r487747c"
    }${
    lib.optionalString (config.androidVersion == 13) "r450784d"  
    }${
    lib.optionalString (config.androidVersion == 12) "r416183b1"
    }${
    lib.optionalString (config.androidVersion == 11) "r383902b1"  
    }${
    lib.optionalString (config.androidVersion == 10) "r353983c1"
    }";

  # TODO modularize in a config file
  buildScriptFor = {
    "coral" = "build/build.sh";
    "sunfish" = "build/build.sh";
    "redfin" = "build/build.sh";
    "raviole" = "build_slider.sh";
    "bluejay" = "build_bluejay.sh";
    "pantah" = "build_cloudripper.sh";
  };

  buildScript = if (config.androidVersion >= 13) then buildScriptFor.${config.deviceFamily} else "build.sh";

  # TODO modularize in a config file
  # This is shared with default.nix
  kernelPrefix = if (config.androidVersion >= 13) then "kernel/android" else "kernel/google";

  # This is for the old compilation script used for 5th and 4th gen pixels.
  buildConfigVar = "private/msm-google/build.config.${if config.deviceFamily != "redfin" then config.deviceFamily else "redbull"}${lib.optionalString (config.deviceFamily == "redfin") ".vintf"}";

  subPaths = prefix: (lib.filter (name: (lib.hasPrefix prefix name)) (lib.attrNames config.source.dirs));
  kernelSources = subPaths sourceRelpath;

  # ? Maybe this unpacking stuff should be modularized to another file. As it stands it is not immediately clear what this functions do or how they are structured.

  unpackSrc = name: src: ''
    shopt -s dotglob
    rm -rf ${name}
    mkdir -p $(dirname ${name})
    cp -r ${src} ${name}
  '';

  # TODO: Style - Hard to parse
  linkSrc = name: c: lib.optionalString (lib.hasAttr "linkfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      ln -rs ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.linkfiles));

  # TODO: Style - Hard to parse
  copySrc = name: c: lib.optionalString (lib.hasAttr "copyfiles" c) (lib.concatStringsSep "\n" (map
    ({ src, dest }: ''
      mkdir -p $(dirname ${sourceRelpath}/${dest})
      cp -r ${name}/${src} ${sourceRelpath}/${dest}
    '')
    c.copyfiles));

  # TODO: Style - Hard to parse
  unpackCmd = name: c: lib.concatStringsSep "\n" [ (unpackSrc name c.src) (linkSrc name c) (copySrc name c) ];

  # TODO: Style - Hard to parse
  unpackSrcs = sources: (lib.concatStringsSep "\n"
    (lib.mapAttrsToList unpackCmd (lib.filterAttrs (name: src: (lib.elem name sources)) config.source.dirs)));

  # the kernel build scripts deeply assume clang as of android 13
  # The version of related LLVM packages to bring is linked to the correct clang version used.
  # ? Do newer llvm versions have adequate support for older clang versions? do we really need to change this depending on which clang one uses?
  # TODO select correct version based off the android version being built
  llvm = pkgs.llvmPackages_15;

  # ? A choice between stdenv or stdenv? I'll comment it out until this is clear.
  #stdenv = if (config.androidVersion >= 13) then pkgs.stdenv else pkgs.stdenv;
  stdenv = pkgs.stdenv;

  # TODO modularize in a config file
  # This is shared with default.nix
  repoName = {
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.deviceFamily;

  # TODO modularize in a config file
  # This is shared with default.nix
  sourceRelpath = "${kernelPrefix}/${repoName}";

  # TODO modularize in a config file
  builtKernelName = {
    "flame" = "coral";
    "sunfish" = "coral";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.device;

  # ? Why redfin has a different path?
  builtRelpath = "device/google/${builtKernelName}-kernel${lib.optionalString (config.deviceFamily == "redfin" && config.variant != "user") "/vintf"}";

  # * Older builds have some issues with glibc and missing symbols. I leave this here commented to (somehow) later on configure older builds to use older packages.
  # oldPkgs = import
  #   (builtins.fetchTarball {
  #     url = "https://github.com/NixOS/nixpkgs/archive/1b7a6a6e57661d7d4e0775658930059b77ce94a4.tar.gz";
  #     sha256 = "sha256:12k1yz0z6qjl0002lsay2cbwvrwqfy23w611zkh6wyjn97nqqvjc";
  #   })
  #   { };

  kernel = config.build.mkAndroid (rec {
    name = "grapheneos-${builtKernelName}-kernel";
    inherit (config.kernel) patches postPatch;

    nativeBuildInputs = with pkgs; [
      perl
      bc
      nettools
      openssl
      rsync
      gmp
      libmpc
      mpfr
      lz4
      which
      nukeReferences
      ripgrep
      glibc.dev.dev.dev
      glibc_multi.dev
      pkg-config
      autoPatchelfHook
      coreutils
      gawk
    ] ++ lib.optionals (config.androidVersion >= 12) [
      python
      python3
      bison
      flex
      cpio
      zlib
    ] ++ lib.optionals (config.androidVersion >= 13) [
      git
      #libelf
      elfutils
      lld
    ];

    unpackPhase = ''
      set -eo pipefail
      shopt -s dotglob
      ${unpackSrcs kernelSources}
      chmod -R a+w .
      runHook postUnpack
    '';

    postUnpack = "cd ${sourceRelpath}";

    # Useful to use upstream's build.sh to catch regressions if any dependencies change
    prePatch = ''
      for d in `find . -type d -name '*lib*'`; do
        addAutoPatchelfSearchPath $d
      done
      autoPatchelf prebuilts${lib.optionalString (config.androidVersion <= 13) "-master"}/clang/host/linux-x86/clang-${clangVersion}/bin
      sed -i '/unset LD_LIBRARY_PATH/d' build/_setup_env.sh
    '';

    preBuild = ''
      mkdir -p ../../../${builtRelpath} out
      chmod a+w -R ../../../${builtRelpath} out

      # * The current way of fetching resources from the processed manifest misses something and this directory and symlink are not present after fetching everything
      mkdir -p private/gs-google/arch/arm64/boot/dts/google/devices
      ln -s -r private/devices/google/${builtKernelName}/dts private/gs-google/arch/arm64/boot/dts/google/devices/${builtKernelName}
    '';

    buildPhase =
      let
        useCodenameArg = config.androidVersion <= 12;
      in
      ''
        set -eo pipefail
        ${preBuild}

        ${
          # ! This is missing KBUILD envvars for pre-redfin devices. 
          # TODO: add KBUILD env vars for pre-redfin
          if postRaviole
          then "LTO=full BUILD_AOSP_KERNEL=1 cflags='--sysroot /usr '"
          else "BUILD_CONFIG=${buildConfigVar} HOSTCFLAGS='--sysroot /usr '"
        } \
        LD_LIBRARY_PATH="/usr/lib/:/usr/lib32/" \
        ./${buildScript} \
        ${lib.optionalString useCodenameArg builtKernelName}

        ${postBuild}
      '';

    postBuild = ''
      cp -r out/${
        if postRaviole
        then "mixed"
        else 
          if postRedfin
          then "android-msm-pixel-4.19"
          else "android-msm-pixel-4.14"
      }/dist/* ../../../${builtRelpath}
    '';

    installPhase = ''
      cp -r ../../../${builtRelpath} $out
    '';
  });

in
mkIf (config.flavor == "grapheneos" && config.kernel.enable) (mkMerge [
  {
    kernel.name = kernel.name;
    kernel.src = pkgs.writeShellScript "unused" "true";
    kernel.buildDateTime = mkDefault config.source.dirs.${sourceRelpath}.dateTime;
    kernel.relpath = mkDefault builtRelpath;

    build.kernel = kernel;
  }
])
