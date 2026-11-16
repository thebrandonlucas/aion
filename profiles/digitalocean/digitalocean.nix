# What a DigitalOcean droplet needs of a NixOS machine that kai installs on
# it with Disk(SingleDisk("/dev/vda")). kai's nixos-facter report brings the
# virtio drivers and the disk layout comes from Disk, so this only adds what
# neither knows: the QEMU guest agent and the serial console DigitalOcean's
# recovery console reads. Networking is NixOS's default DHCP, which
# DigitalOcean serves for the droplet's public IPv4.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.kernelParams = [ "console=ttyS0" ];
}
