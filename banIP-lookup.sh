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
upstream="8.8.8.8"
input1="input1.txt"
input2="input2.txt"
input3="input3.txt"
update="false"

# sanity pre-checks
#
if [ ! -x "${dig_tool}" ] || [ ! -x "${awk_tool}" ]; then
	printf "%s\n" "ERR: general pre-check failed"
	exit 1
fi

for domain in ${check_domains}; do
	out="$("${dig_tool}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=1 2>/dev/null)"
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
feeds='yoyo__https://pgl.yoyo.org/adservers/serverlist.php?hostformat=nohtml&showintro=0&mimetype=plaintext__/^([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+([[:space:]]|$)/{printf"%s\n",tolower($1)}
	adguard__https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt__BEGIN{FS="[\\|^|\\r]"}/^\|\|([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+[\/\^\\r]+$/{printf"%s\n",tolower($3)}
	oisdbasic__https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_basic.txt__/^([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+([[:space:]]|$)/{printf"%s\n",tolower($1)}
	stevenblack__https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts__/^0\.0\.0\.0[[:space:]]+([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+([[:space:]]|$)/{printf"%s\n",tolower($2)}
	oisdnsfw__https://raw.githubusercontent.com/sjhgvr/oisd/main/dbl_nsfw.txt__/^([[:alnum:]_-]{1,63}\.)+[[:alpha:]]+([[:space:]]|$)/{printf"%s\n",tolower($1)}'

for feed in ${feeds}; do
	: >"./${input1}"
	: >"./${input2}"
	: >"./${input3}"
	: >"./ipv4.tmp"
	: >"./ipv6.tmp"

	feed_name="${feed%%__*}"
	feed_url="${feed#*__}"
	feed_url="${feed_url%__*}"
	feed_regex="${feed##*__}"
	feed_start1="$(date "+%s")"
	curl "${feed_url}" --connect-timeout 20 --fail --silent --show-error --location | "${awk_tool}" "${feed_regex}" >"./${input1}"
	feed_cnt="$("${awk_tool}" 'END{printf "%d",NR}' "./${input1}" 2>/dev/null)"
	printf "%s\n" "::: Start processing '${feed_name}', overall domains: ${feed_cnt}"

	# domain processing (first run)
	#
	cnt="0"
	while IFS= read -r domain; do
		(
			out="$("${dig_tool}" "${domain}" A "${domain}" AAAA +noall +answer +time=5 +tries=1 2>/dev/null)"
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
				else
					printf "%s\n" "$domain" >>"./${input2}"
				fi
			fi
		) &
		hold1="$((cnt % 512))"
		hold2="$((cnt % 4096))"
		[ "${hold1}" = "0" ] && sleep 3
		[ "${hold2}" = "0" ] && wait
		cnt="$((cnt + 1))"
	done <"./${input1}"
	wait
	error_cnt="$("${awk_tool}" 'END{printf "%d",NR}' "./${input2}" 2>/dev/null)"
	feed_end="$(date "+%s")"
	feed_duration="$(((feed_end - feed_start1) / 60))m $(((feed_end - feed_start1) % 60))s"
	printf "%s\n" "::: First run, duration: ${feed_duration}, processed domains: ${cnt}, error domains: ${error_cnt}"

	# domain processing (second run)
	#
	feed_start2="$(date "+%s")"
	cnt="0"
	while IFS= read -r domain; do
		(
			out="$("${dig_tool}" "@${upstream}" "${domain}" A "${domain}" AAAA +noall +answer +time=10 +tries=1 2>/dev/null)"
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
				else
					printf "%s\n" "$domain" >>"./${input3}"
				fi
			fi
		) &
		hold1="$((cnt % 512))"
		hold2="$((cnt % 4096))"
		[ "${hold1}" = "0" ] && sleep 5
		[ "${hold2}" = "0" ] && wait
		cnt="$((cnt + 1))"
	done <"./${input2}"
	wait
	error_cnt="$("${awk_tool}" 'END{printf "%d",NR}' "./${input3}" 2>/dev/null)"
	feed_end="$(date "+%s")"
	feed_duration="$(((feed_end - feed_start2) / 60))m $(((feed_end - feed_start2) % 60))s"
	printf "%s\n" "::: Second run, duration: ${feed_duration}, processed domains: ${cnt}, error domains: ${error_cnt}"

	# sanity re-check
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
	feed_end="$(date "+%s")"
	feed_duration="$(((feed_end - feed_start1) / 60))m $(((feed_end - feed_start1) % 60))s"
	printf "%s\n" "::: Finished processing '${feed_name}', duration: ${feed_duration}, all/unique IPv4: ${cnt_tmpv4}/${cnt_ipv4}, all/unique IPv6: ${cnt_tmpv6}/${cnt_ipv6}"
done

# error out
#
if [ "${update}" = "false" ]; then
	printf "%s\n" "ERR: general re-check failed"
	exit 1
fi
