# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

# This is an example configuration that I personally use for my device.
# Please read the manual instead of simply copying this file for your own use.

{ config, pkgs, lib, ... }:

let
  myDomain = "bluejay.queso.win";
in
{
  # These are required options, but commented out here since I set it programmatically for my devices elsewhere
  device = "bluejay";
  flavor = "grapheneos"; # "vanilla" is another option

  # buildDateTime is set by default by the flavor, and is updated when those flavors have new releases.
  # If you make new changes to your build that you want to be pushed by the OTA updater, you should set this yourself.
  #buildDateTime = 1584398664; # Use `date "+%s"` to get the current time

  #signing.enable = false;
  # signing.keyStorePath = "/var/secrets/android-keys"; # A _string_ of the path for the key store.

  # Build with ccache
  #ccache.enable = true;

  apv.enable = false;
  adevtool.hash = "sha256-OJk4x1VyYAUfG8McXIdaPAacyF/fZUmblxnf6eVc4Jo=";

}
