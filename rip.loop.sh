#!/usr/bin/env bash
for p in ddrescue blktool file mount smartctl cdrdao bchunk toc2cue lame fdflush yesno;do
	if ! command -v "${p}";then
		echo "Please install ${p}"
		exit 1
	fi
done
if command -v wodim;then
	CDRE='wodim'
elif command -v cdrecord; then
	CDRE='cdrecord'
else
	echo "Please install womid or cdrecord"
	exit 1
fi
if [ -z "${1}" ]; then
	echo "Please provide a block device"
	exit 1
fi
if [ ! -b "${1}" ]; then
	echo "${1} is not a block device"
	exit 1
fi
workdir="$(pwd)"
removable=no
unremovable=no
major="$((16#$(stat -c '%t' "${1}" ) ))" 
vendor="$(smartctl -i "${1}" | grep ^Vendor | awk '{print($2)}')"
devtype="$( grep -m 1 -w "${major}" /proc/devices | awk '{print($2)}' )"
if [ "${devtype}" == 'sr' ] || [ "${vendor}" == 'IOMEGA' ]; then
       removable=yes
fi
if [ "${devtype}" == 'sr' ]; then
       unremovable=yes
fi
blktool "${1}" readonly on
echo -n "ReadOnly: "
blktool "${1}" readonly
while true;do
	disk=default
	cd "${workdir}" || exit 1
	read -e -p "${1}:Name>" name
	if [ -e "${name}.img" ] || [ -e "${name}.map" ] || [ -e "${name}" ]; then
		echo "${name} already exists"
		sname="$( awk '{print($1)}' <<< "${name}" )"
		ls -lah "${sname}"*
		continue
	fi
	if [ -z "${name}" ]; then
		echo "Name cannot be blank"
		continue
	fi
	if [ "${name}" = '+' ];then
		index="$( rev <<< "${lastname}" | cut -d' ' -f 1 | rev )"
		if ! [ "${index}" -gt -1 ]; then
			echo "Last field not real integer"
			continue
		fi
		fields="$( wc -w <<< "${lastname}" )"
		off=1
		name="$( cut -d' ' -f "1-$(( fields - 1 ))" <<< "${lastname}" ) $(( index + off ))"
		while [ -e "${name}.img" ] || [ -e "${name}.map" ] || [ -e "${name}" ];do
			off="$(( off + 1 ))"
			name="$( cut -d ' ' -f "1-$(( fields - 1 ))" <<< "${lastname}") $(( index + off ))"
			if [ "${off}" -gt 512 ]; then
				echo "Something is wrong, try something else"
				continue
			fi
		done
	fi
	if touch "${name}"; then
		rm -f "${name}"
	else
		echo "Invalid name: ${name}"
	       	continue
	fi	
	if [ -e "${name} (corrupt)" ] || [ -e "${name} (corrupt).img" ] || [ -e "${name} (corrupt).map" ]; then
		echo "Name already tried and failed"
		continue
	fi
	if [ "${unremovable}" == 'yes' ]; then
		eject -t "${1}"
		toc="$( "${CDRE}" -v "dev=${1}" -toc )"
		echo -e "${toc}"
		if grep -v lout <<< "${toc}" | grep 'mode: -1' ; then
			echo "Audio disk"
			disk=audio
		fi
	fi
	echo "Flushing"
	fdflush "${1}"
	sync
	blktool "${1}" readonly on
	echo -n "ReadOnly: "
	blktool "${1}" readonly
	echo "Ripping ${name}"
	if [ "${disk}" == 'audio' ]; then
		MARKFAIL=no
		mkdir "${name}"
		cd "${name}" || exit 1
		echo "If data portion of rip fails, follow up with: ddrescue -S --retry-passes=5 \"${1}\" \"${name}.img\" \"${name}.map\""
		if ! cdrdao read-cd --read-raw --device "${1}" --datafile "${name}.bin" "${name}.toc";then
			echo -e "Failed:cdrdao read-cd --device ${1} --datafile ${name}.bin ${name}.toc\nTry ddrescue? [Y/N]>"
			if yesno; then
				ddrescue -S --retry-passes=5 "${1}" "${name}.img" "${name}.map"
			fi
			echo "Mark corrupt? [Y/N]>"
			if yesno; then
				MARKFAIL=yes
			fi
		fi
		toc2cue "${name}.toc" "${name}.cue"
		bchunk -w -s "${name}.bin" "${name}.cue" "${name} "
		if [ -e "${name} 01.ugh" ]; then
			mv "${name} 01.ugh" "${name}.iso"
		fi
		for w in *.wav;do
			lame -V4 -h -b 128 --vbr-new "${w}" "${w/.wav/.mp3}"
		done
		mv "${name} 01.iso" "${name}.iso"
		mkdir "tm${$}"
		if mount -o ro,loop "${name}.iso" "./tm${$}";then
			ls "./tm${$}/"
			umount "./tm${$}"
		else
			echo "Unable to mount ${name}"
		fi
		rmdir "tm${$}"
		if [ "${MARKFAIL}" == 'yes' ]; then
			cd "${workdir}" || exit 1
			mv "${name}" "${name} (corrupt)"
		else
			rm "${name}.map"
		fi
	else 
		echo "ddrescue -S -M -A --retry-passes=5 \"${1}\" \"${name}.img\" \"${name}.map\""
		ddrescue -S --retry-passes=5 "${1}" "${name}.img" "${name}.map"
		err="$( awk -F \# '{print($1)}' "${name}.map" | grep -v ^$ | grep -c -v + )"
		if [ "${err}" -lt 1 ]; then
			echo "Sucsess"
			mkdir "tm${$}"
			if mount -o ro,loop "${name}.img" "./tm${$}";then
				ls "./tm${$}/"
				umount "./tm${$}"
			else
				echo "Unable to mount ${name}"
			fi
			rmdir "./tm${$}"
			file "${name}.img"
		else
			echo "Error: ${err} unreadable blocks"
			mv "${name}.img" "${name} (corrupt).img"
			mv "${name}.map" "${name} (corrupt).map"
			echo "ddrescue -S -M -A --retry-passes=5 \"${1}\" \"${name} (corrupt).img\" \"${name} (corrupt).map\"" 
		fi
	fi
	sname="$( awk '{print($1)}' <<< "${name}" )"
	ls -lah "${sname}"*
	if [ "${removable}" == 'yes' ]; then
		eject "${1}"
	fi
	export lastname="${name}"
done
