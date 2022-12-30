#!/bin/sh
# banIP-lookup - retrieve IPv4/IPv6 addresses via dig from downloaded domain lists
# and write the adjusted output to separate lists (IPv4/IPv6 addresses plus domains)
# Copyright (c) 2022-2023 Dirk Brenken (dev@brenken.org)
#
# This is free software, licensed under the GNU General Public License v3.

# disable (s)hellcheck in release
# shellcheck disable=all

# prepare environment
#
export LC_ALL=C
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"
dig_tool="$(command -v dig)"
awk_tool="$(command -v awk)"
check_domains="google.com heise.de openwrt.org"
upstream="1.1.1.1"
input="input.txt"
update="false"

# sanity pre-checks
#
if [ ! -x "${dig_tool}" ] || [ ! -x "${awk_tool}" ] || [ -z "${upstream}" ]; then
	printf "%s\n" "ERR: general pre-check failed"
	exit 1
fi

for domain in ${check_domains}; do
	out="$("${dig_tool}" "@${upstream}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=1 2>/dev/null)"
	if [ -z "${out}" ]; then
		printf "%s\n" "ERR: domain pre-check failed"
		exit 1
	else
		ips="$(printf "%s" "${out}" | "${awk_tool}" '/^.*[[:space:]]+IN[[:space:]]+A{1,4}[[:space:]]+/{printf "%s ",$NF}' 2>/dev/null)"
		if [ -z "${ips}" ]; then
			printf "%s\n" "ERR: ip pre-check failed"
			exit 1
		fi
	fi
done

# download domains/host files
#
feeds="adguard_https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/BaseFilter/sections/adservers.txt
		yoyo_https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&showintro=0&mimetype=plaintext
		stevenblack_https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
		oisdbasic_https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_basic.txt
		oisdnsfw_https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_nsfw.txt"

for feed in ${feeds}; do
	feed_name="${feed%%_*}"
	feed_url="${feed#*_}"
	printf "%s\n" "$(date +%D-%T) ::: Start processing '${feed_name}' ..."
	: >"./${input}"
	: >"./ipv4.tmp"
	: >"./ipv6.tmp"
	curl "${feed_url}" --connect-timeout 20 --fail --silent --show-error --location | "${awk_tool}" 'BEGIN{RS="([[:alnum:]_-]{1,63}\\.)+[[:alpha:]]+"}!/^[[:space:]]*[#|!]/{if(!seen[RT]++)printf "%s\n",tolower(RT)}' >"./${input}"

	# domain processing
	#
	cnt="1"
	domain_cnt="0"
	while IFS= read -r domain; do
		(
			out="$("${dig_tool}" "@${upstream}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=5 2>/dev/null)"
			if [ -n "${out}" ]; then
				ips="$(printf "%s" "${out}" | "${awk_tool}" '/^.*[[:space:]]+IN[[:space:]]+A{1,4}[[:space:]]+/{printf "%s ",$NF}' 2>/dev/null)"
				if [ -n "${ips}" ]; then
					for ip in ${ips}; do
						if [ "${ip%%.*}" = "0" ] || [ -z "${ip%%::*}" ] || [ "${ip}" = "1.1.1.1" ] || [ "${ip}" = "8.8.8.8" ]; then
							continue
						else
							if ipcalc-ng -cs "${ip}"; then
								if [ "${ip##*:}" = "${ip}" ]; then
									printf "%-20s%s\n" "${ip}" "# ${domain}" >>"./ipv4.tmp"
								else
									printf "%-40s%s\n" "${ip}" "# ${domain}" >>"./ipv6.tmp"
								fi
							fi
						fi
					done
				fi
			fi
		) &
		domain_cnt="$((domain_cnt + 1))"
		hold="$((cnt % 64))"
		if [ "${hold}" = "0" ]; then
			wait
			cnt="1"
		else
			cnt="$((cnt + 1))"
		fi
	done <"./${input}"
	wait

	# sanity re-checks
	#
	if [ ! -s "./ipv4.tmp" ] || [ ! -s "./ipv6.tmp" ]; then
		printf "%s\n" "ERR: '${feed_name}' re-check failed"
		continue
	fi

	# final sort/merge step
	#
	update="true"
	sort -b -u -n -t. -k1,1 -k2,2 -k3,3 -k4,4 "./ipv4.tmp" >"./${feed_name}-ipv4.txt"
	sort -b -u -k1,1 "./ipv6.tmp" >"./${feed_name}-ipv6.txt"
	cnt_tmpv4="$("${awk_tool}" 'END{printf "%d",NR}' "./ipv4.tmp" 2>/dev/null)"
	cnt_tmpv6="$("${awk_tool}" 'END{printf "%d",NR}' "./ipv6.tmp" 2>/dev/null)"
	cnt_ipv4="$("${awk_tool}" 'END{printf "%d",NR}' "./${feed_name}-ipv4.txt" 2>/dev/null)"
	cnt_ipv6="$("${awk_tool}" 'END{printf "%d",NR}' "./${feed_name}-ipv6.txt" 2>/dev/null)"
	printf "%s\n" "$(date +%D-%T) ::: Finished processing '${feed_name}', domains: ${domain_cnt}, all/unique IPv4: ${cnt_tmpv4}/${cnt_ipv4}, all/unique IPv6: ${cnt_tmpv6}/${cnt_ipv6}"
done

# error out
#
if [ "${update}" = "false" ]; then
	printf "%s\n" "ERR: general re-check failed"
	exit 1
fi
