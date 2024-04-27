# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ config, pkgs, lib, ... }:
let
  inherit (lib)
    optional optionalString optionalAttrs elem
    mkIf mkMerge mkDefault mkForce;

  upstreamParams = import ./upstream-params.nix;
  grapheneOSRelease = "${config.apv.buildID}${upstreamParams.buildNumber}";

  # -----------------------------------------
  # Current device support by GrapheneOS. 
  # * Make sure this is updated.
  activeDeviceFamilies = [ "barbet" "bluejay" "pantah" ];
  legacyDeviceFamilies = [ "coral" "sunfish" "bramble" "redfin" ];
  obsoleteDeviceFamilies = [ "crosshatch" "bonito" ];
  # ----------------------------------------

  # -----------------------------------------
  # Current Android Version support by GrapheneOS. 
  # * Make sure this is updated.
  supportedAndroidVersions = [ 13 14 ];
  # ----------------------------------------

  phoneDeviceFamilies = activeDeviceFamilies ++ legacyDeviceFamilies ++ obsoleteDeviceFamilies;
  supportedDeviceFamilies = phoneDeviceFamilies ++ [ "generic" ];

  # Last GrapheneOS Build Number that had a build ID, before unification 
  # Check https://grapheneos.org/releases#2023062300
  lastLegacyTagBuildNumber = "2023061402";

  kernelPrefix = if config.androidVersion >= 13 then "kernel/android" else "kernel/google";

  kernelRepoName = {
    "sargo" = "crosshatch";
    "bonito" = "crosshatch";
    "flame" = "coral";
    "sunfish" = "coral";
    "bramble" = "redbull";
    "redfin" = "redbull";
    "barbet" = "redbull";
    "oriole" = "raviole";
    "raven" = "raviole";
    "bluejay" = "bluejay";
    "panther" = "pantah";
    "cheetah" = "pantah";
  }.${config.device} or config.deviceFamily;

  kernelSourceRelpath = "${kernelPrefix}/${kernelRepoName}";

  kernelSources = lib.mapAttrs'
    (path: src: {
      name = "${kernelSourceRelpath}/${path}";
      value = src // {
        enable = false;
      };
    })
    (lib.importJSON (./kernel-repos/repo- + "${kernelRepoName}-${grapheneOSRelease}.json"));

  isDeviceActive = elem config.deviceFamily activeDeviceFamilies;
  isDeviceLegacy = elem config.deviceFamily legacyDeviceFamilies;
  isDeviceObsolete = elem config.deviceFamily obsoleteDeviceFamilies;
  isAndroidVersionSupported = elem config.androidVersion supportedAndroidVersions;
  isNewTagBuild = (lib.strings.toInt upstreamParams.buildNumber) > (lib.strings.toInt lastLegacyTagBuildNumber);

  warnings = (
    optional ((config.device != null) && !(elem config.deviceFamily phoneDeviceFamilies))
      "${config.device} is not a supported device for GrapheneOS"
  )

  ++ (
    optional (!(isAndroidVersionSupported)) "Unsupported androidVersion (!= 13 or 14) for GrapheneOS"
  )

  ++ (
    optional (isDeviceLegacy) "[${lib.concatStringSep ", " legacyDeviceFamilies}] are considered legacy devices, only receive basic rebased updates from the AOSP project, and do not receive direct GrapheneOS support"
  );

  deviceTest =
    if isDeviceObsolete
    then throw "[${lib.concatStringSep ", " obsoleteDeviceFamilies}] are considered obsolete devices and grapheneos can't be built for them"
    else true;

in
mkIf (config.flavor == "grapheneos") (mkMerge [
  rec {
    androidVersion = mkDefault 13;
    buildNumber = mkDefault upstreamParams.buildNumber;
    buildDateTime = mkDefault upstreamParams.buildDateTime;

    productNamePrefix = mkDefault "";

    # Match upstream user/hostname
    envVars = {
      BUILD_USERNAME = "grapheneos";
      BUILD_HOSTNAME = "grapheneos";
    };
    source.dirs = (lib.importJSON (./. + "/repo-${grapheneOSRelease}.json") // kernelSources);

    apv.enable = mkIf (config.androidVersion <= 12 && elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);



    apv.buildID = mkDefault (
      if (elem config.device (activeDeviceFamilies ++ legacyDeviceFamilies))
      then
        (
          # Legacy devices get AOSP patches rebased on their tag
          # therefore only actively supported devices get this blanked
          if isNewTagBuild && isDeviceActive
          then ""
          else "TQ3A.230605.012."
        )
      else "TP1A.221005.002.B2."
    );

    adevtool.enable = mkIf (config.androidVersion >= 13 && elem config.deviceFamily phoneDeviceFamilies) (mkDefault true);
    adevtool.buildID = config.apv.buildID;

    # Not strictly necessary for me to set these, since I override the source.dirs above
    source.manifest.url = mkDefault "https://github.com/GrapheneOS/platform_manifest.git";
    source.manifest.rev = mkDefault "refs/tags/${grapheneOSRelease}";

  }
  {
    # ? Is Soong Still supported by this project?
    # Disable setting SCHED_BATCH in soong. Brings in a new dependency and the nix-daemon could do that anyway.
    source.dirs."build/soong".patches = [
      (pkgs.fetchpatch {
        url = "https://github.com/GrapheneOS/platform_build_soong/commit/76723b5745f08e88efa99295fbb53ed60e80af92.patch";
        sha256 = "0vvairss3h3f9ybfgxihp5i8yk0rsnyhpvkm473g6dc49lv90ggq";
        revert = true;
      })
    ];

    # ? Is this still necesary? 
    # hack to make sure the out directory remains writeable after copying files/directories from /nix/store mounted sources
    source.dirs."prebuilts/build-tools".postPatch = mkIf (config.androidVersion >= 13) ''
      pushd path/linux-x86
      mv cp .cp-wrapped
      cp ${pkgs.substituteAll { src = ./fix-perms.sh; inherit (pkgs) bash; }} cp

      chmod +x cp
      popd
    '';

    # No need to include kernel sources in Android source trees since we build separately
    # * Commented out unsupported devices
    #source.dirs."${kernelPrefix}/marlin".enable = false;
    #source.dirs."${kernelPrefix}/wahoo".enable = false;
    #source.dirs."${kernelPrefix}/crosshatch".enable = false;
    #source.dirs."${kernelPrefix}/bonito".enable = false;
    source.dirs."${kernelPrefix}/coral".enable = false;
    source.dirs."${kernelPrefix}/sunfish".enable = false;
    source.dirs."${kernelPrefix}/redbull".enable = false;
    source.dirs."${kernelPrefix}/barbet".enable = false;
    source.dirs."${kernelPrefix}/raviole".enable = false;
    source.dirs."${kernelPrefix}/bluejay".enable = false;
    source.dirs."${kernelPrefix}/pantah".enable = false;

    kernel.enable = mkDefault (elem config.deviceFamily phoneDeviceFamilies);

    # Enable Vanadium (GraphaneOS's chromium fork).
    apps.vanadium.enable = mkDefault true;
    webview.vanadium.enable = mkDefault true;
    webview.vanadium.availableByDefault = mkDefault true;

    apps.seedvault.includedInFlavor = mkDefault true;
    apps.updater.includedInFlavor = mkDefault true;

    # Remove upstream prebuilt versions from build. We build from source ourselves.
    removedProductPackages = [ "TrichromeWebView" "TrichromeChrome" "webview" ];
    source.dirs."external/vanadium".enable = false;

    # ? Is this up to date?
    # Override included android-prepare-vendor, with the exact version from
    # GrapheneOS. Unfortunately, Doing it this way means we don't cache apv
    # output across vanilla/grapheneos, even if they are otherwise identical.
    source.dirs."vendor/android-prepare-vendor".enable = false;
    nixpkgs.overlays = [
      (self: super: {
        android-prepare-vendor = super.android-prepare-vendor.overrideAttrs (_: {
          src = config.source.dirs."vendor/android-prepare-vendor".src;
          patches = [
            ./apv/0001-Just-write-proprietary-blobs.txt-to-current-dir.patch
            ./apv/0002-Allow-for-externally-set-config-file.patch
            ./apv/0003-Add-option-to-use-externally-provided-carrier_list.p.patch
          ];
          passthru.evalTimeSrc = builtins.fetchTarball {
            url = "https://github.com/GrapheneOS/android-prepare-vendor/archive/${config.source.dirs."vendor/android-prepare-vendor".rev}.tar.gz";
            inherit (config.source.dirs."vendor/android-prepare-vendor") sha256;
          };
        });
      })
    ];

    # GrapheneOS just disables apex updating wholesale
    signing.apex.enable = false;

    # Extra packages that should use releasekey
    signing.signTargetFilesArgs = [
      "--extra_apks AdServicesApk.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks Bluetooth.apk=$KEYSDIR/${config.device}/bluetooth"
      "--extra_apks HalfSheetUX.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks OsuLogin.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks SafetyCenterResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceConnectivityResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceUwbResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks ServiceWifiResources.apk=$KEYSDIR/${config.device}/releasekey"
      "--extra_apks WifiDialog.apk=$KEYSDIR/${config.device}/releasekey"
    ];
    # Leave the existing auditor in the build--just in case the user wants to
    # audit devices running the official upstream build
  }
])
