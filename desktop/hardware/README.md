# MSI Katana controller snapshot

The msi-ec module was installed locally for kernel 7.2.15-1-omarchy. It reports module version 0.18 and srcversion A182AF2C50B5A24795B712A. Its license is GPL and its upstream source is https://github.com/BeardOverflow/msi-ec. Debug-only build metadata was removed from the exported module. The SHA-256 is recorded in katana-profile.json.

The restore script checks the notebook model, exact kernel and controller firmware before applying the saved fan profile. Hardware setup requires --fan-control. The systemd unit restores the saved profile at boot.
