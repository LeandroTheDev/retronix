{ pkgs, ... }:

{
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "audio" "input" ];
    packages = with pkgs; [
      tree
    ];
  };

  # Seeds new users' home directories (useradd -m copies /etc/skel on account
  # creation) with our retroarch.cfg defaults — doesn't retroactively touch
  # already-existing homes.
  environment.etc.skel = {
    source = ./home;
    recursive = true;
  };
}
