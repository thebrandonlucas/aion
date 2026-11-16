# What a DigitalOcean droplet needs of a NixOS machine that kai installs on
# it with Disk(SingleDisk("/dev/vda")). kai's nixos-facter report brings the
# virtio drivers and the disk layout comes from Disk, so this only adds what
# neither knows: the QEMU guest agent, the serial console DigitalOcean's
# recovery console reads, and the network.
#
# A droplet made from one of DigitalOcean's base images gets its static
# address from a config drive, with no DHCP. cloud-init applies it through
# systemd-networkd and does nothing else: kai owns the hostname, the users
# and the SSH host key its secrets are encrypted to.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.kernelParams = [ "console=ttyS0" ];
  networking.useDHCP = false;
  services.resolved.enable = true;
  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [
        "ConfigDrive"
        "DigitalOcean"
      ];
      preserve_hostname = true;
      ssh_deletekeys = false;
      cloud_init_modules = [ ];
      cloud_config_modules = [ ];
      cloud_final_modules = [ ];
    };
  };
}
