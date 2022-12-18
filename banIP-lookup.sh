#!/bin/sh
# banIP-lookup - retrieve IPv4/IPv6 addresses via dig from downloaded domain lists
# and write the adjusted output to separate lists (IPv4/IPv6 addresses plus domains)
# Copyright (c) 2022 Dirk Brenken (dev@brenken.org)
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

# sanity pre-checks
#
if [ ! -x "${dig_tool}" ] || [ ! -x "${awk_tool}" ] || [ -z "${upstream}" ]; then
	printf "%s\n" "ERR: general pre-check failed"
	exit 1
fi

for domain in ${check_domains}; do
	for resolver in ${upstream}; do
		out="$("${dig_tool}" "@${resolver}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=1 2>/dev/null)"
		if [ -z "${out}" ]; then
			printf "%s\n" "ERR: domain pre-check failed"
			exit 1
		else
			ips="$(printf "%s" "${out}" | "${awk_tool}" '/^.*[[:space:]]+IN[[:space:]]+A{1,4}[[:space:]]+/{printf "%s ",$NF}')"
			if [ -z "${ips}" ]; then
				printf "%s\n" "ERR: ip pre-check failed"
				exit 1
			fi
		fi
	done
done

# download domains/host files
#
feeds="https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_basic.txt
		https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_nsfw.txt"
for feed in ${feeds}; do
	printf "%s\n" "$(date +%D-%T) ::: Start processing '${feed}' ..."
	: >"./${input}"
	: >"./ipv4.tmp"
	: >"./ipv6.tmp"
	output="${feed##*/}"
	output="${output%.*}"
	curl "${feed}" --connect-timeout 20 --fail --silent --show-error --location | awk '/^([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+([[:space:]]|$)/{print tolower($1)}' | sort -u >./input.txt

	# domain processing
	#
	cnt=0
	while IFS= read -r domain; do
		(
			out="$("${dig_tool}" "@${resolver}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=1 2>/dev/null)"
			if [ -n "${out}" ]; then
				ips="$(printf "%s" "${out}" | "${awk_tool}" '/^.*[[:space:]]+IN[[:space:]]+A{1,4}[[:space:]]+/{printf "%s ",$NF}')"
				if [ -n "${ips}" ]; then
					for ip in ${ips}; do
						if [ "${ip%%.*}" = "0" ] || [ "${ip}" = "::" ] || [ "${ip}" = "1.1.1.1" ] || [ "${ip}" = "8.8.8.8" ]; then
							continue
						else
							if [ -n "$(printf "%s" "${ip}" | "${awk_tool}" '/^(([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?)([[:space:]]|$)/{print $1}')" ]; then
								printf "%-20s%s\n" "${ip}" "# ${domain}" >>./ipv4.tmp
							else
								printf "%-40s%s\n" "${ip}" "# ${domain}" >>./ipv6.tmp
							fi
						fi
					done
				fi
			fi
		) &
		hold=$((cnt % 9000))
		[ "${hold}" = "0" ] && wait
		cnt=$((cnt + 1))
	done <"./${input}"
	wait

	# sanity re-checks
	#
	if [ ! -s "./ipv4.tmp" ] || [ ! -s "./ipv6.tmp" ]; then
		printf "%s\n" "ERR: general re-check failed"
		exit 1
	fi

	# final sort/merge step
	#
	sort -b -u -n -t. -k1,1 -k2,2 -k3,3 -k4,4 "./ipv4.tmp" >"./${output}-ipv4.txt"
	sort -b -u -k1,1 "./ipv6.tmp" >"./${output}-ipv6.txt"
	rm "./ipv4.tmp" "./ipv6.tmp" "./${input}"
	printf "%s\n" "$(date +%D-%T) ::: Finished processing '${feed}'"
done
