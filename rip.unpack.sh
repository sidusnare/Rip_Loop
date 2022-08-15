#!/bin/bash
OGPWD="$( pwd )"
mount="/tmp/rip.extract.mount.${$}"
if [ -e "${mount}" ]; then
	echo "Mount point exists, aborting"
	exit 1
fi
trap "umount ${mount};sleep 2;umount -lf ${mount};rmdir ${mount};exit 1" SIGHUP SIGINT SIGTERM
mkdir "${mount}"
for i in "${@}";do
	cd "${OGPWD}" || exit 1
	echo "Working on ${i}"
	full="$( readlink -f "${i}")"
	basedir="$( dirname "${full}" )"
	file="$( basename "${full}" )"
	ext="${file##*.}"
	if [ "${ext}" == "${file}" ]; then
		file=''
	fi
	shortname="$( basename "${file}" ".${ext}" )"
	if [ -z "${ext}" ]; then
		dir="${full}.dir"
	else
		dir="${basedir}/${shortname}"
	fi
	echo -e "\tFull filename:\t${full}\n\tBase dir:\t${basedir}\n\tFilename:\t${file}\n\tExtension:\t${ext}\n\tShort name:\t${shortname}\n\tTarget dir:\t${dir}"
	if [ -e "${dir}" ]; then
		echo "Warning: Directory already exists: ${dir}"
	fi
	if ! mount "${full}" "${mount}"; then
		if [ ! -e "${dir}" ]; then
			mkdir "${dir}"
		fi
		cd "${dir}" || continue
		foremost "${full}"
	fi
	if ! cp -arfv "${mount}" "${dir}"; then
		umount "${mount}"
		cd "${dir}" || continue
		foremost "${full}"
	fi
	lc=0
	while grep "${mount}" /proc/mounts;do
		lc=$(( lc + 1 ))
		sync
		sleep 1
		umount "${mount}"
		if [ "${lc}" -gt 10 ]; then
			fuser -k -9 -m "${mount}"
		fi
		if [ "${lc}" -gt 20 ]; then
			umount -f "${mount}"
		fi
		if [ "${lc}" -gt 30 ]; then
			umount -l -f "${mount}"
		fi

	done
done

rmdir -v "${mount}"
