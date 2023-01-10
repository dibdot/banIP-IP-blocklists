# banIP-IP-blocklists

This repo contains the IPv4/IPv6 addresses of ad-/porn-related external domain/host files. Currently the following external domain feeds are supported:

* adaway, see (https://github.com/AdAway/adaway.github.io) for details
* adguard, see (https://github.com/AdguardTeam/AdguardSDNSFilter) for details
* adguardtrackers, see (https://github.com/AdguardTeam/cname-trackers) for details
* oisdbasic, see (https://oisd.nl/) for details
* oisdnsfw, see (https://oisd.nl/) for details
* stevenblack, see (https://github.com/StevenBlack/hosts) for details
* yoyo, see (https://pgl.yoyo.org/adservers/) for details

The `banIP-lookup.sh` script runs automatically once a day via github actions to extract and update the IP addresses of the external feeds.

Have fun!
Dirk Brenken
