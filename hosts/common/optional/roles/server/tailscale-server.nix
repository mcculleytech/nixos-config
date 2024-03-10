{
 services.tailscale.useRoutingFeatures = "server";
 # enable ip forwarding for TS Router.
 boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
 boot.kernel.sysctl."'net.ipv6.conf.all.forwarding" = 1;
}