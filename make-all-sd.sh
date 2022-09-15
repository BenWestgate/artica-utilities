#!/usr/bin/env bash
# Copyright (c) 2022 Ben Westgate
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#################################################
# This script will setup persistence on the currently running tails, then ask to insert additional devices to make Persistent Tails clones on them. 
# Only /home/amnesia/Persistent will be mounted from the running Tail's persistence before restarting, more things can be persisted if needed.
#
# Parameter $1 = passphrase
# Parameter $2 = iteration time (ms) to unlock persistence, 2000 is default, longer iteration is more costly to crack.
# Parameter $3 = max memory for password hashing in kB, suggest 100000 as minimum, 4194304 is best
# Parameter $4 = source directory to setup new persistent volumes with
#	This gets rsync'd into new persistent filesystems.
#	To backup a currently running system, use '/live/persistence/TailsData_unlocked/'
# Parameter $5 = Number of clones to make.

readonly TAILS_PART=$(mount | grep /lib/live/mount/medium | cut -f1 -d' ')
readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
readonly MAX_MEMORY=$3	# memory kB used for key-stretching, more is more costly to crack, but systems with < value used will not be able to open the encryption
readonly RUNNING_DEVICE=${TAILS_PART%?}	# strips partition number off device
#################################################
# Adds a second partition to device, creates tails persistence and copies file system to it, then closes encryption
# Parameters $1 = passphrase
# Parameter $2 = iteration time (ms) to unlock persistence, 2000 is default, longer iteration is more costly to crack.
# Parameter $3 = max memory for password hashing in kB, suggest 100000 as minimum, 4194304 is best
# Parameter $4 = source directory to setup new persistent volumes with
# Paramater $5 = device to make persistent
#################################################
add_persistence () {
	echo "n



t

27
w" | sudo --askpass fdisk $5		# creates linux reserved partition in free-space
	echo "name
2
TailsData
q" | sudo --askpass parted $5
# Sets up LUKS2 volume and file system on device then mounts it.
	printf "$1" | sudo cryptsetup luksFormat --batch-mode --verbose --pbkdf=argon2id --iter-time=$2 --pbkdf-memory=$3 --batch-mode "$5"2
	printf "$1" | sudo cryptsetup --verbose open "$5"2 TailsData_unlocked
	sudo mkfs.ext4 -F -L 'TailsData' /dev/mapper/TailsData_unlocked
	sleep 0.1
	sudo mount /dev/mapper/TailsData_unlocked /media/$USER/TailsData
	# add these if you need to change some file names between persistence partitions.
	# mv $SCRIPT_DIR/TailsData/Persistent/SD_*.txt SD_$i.txt
	# mv $SCRIPT_DIR/TailsData/Persistent/setup*.txt setup$i.txt
	sudo rsync -PaSHAXv --del "$4" /media/$USER/TailsData
	sudo umount /media/$USER/TailsData
}
 
clear -x

echo "#!/usr/bin/env bash
zenity --password --title='Enter Admin Password'" > $SCRIPT_DIR/askpass.sh
export SUDO_ASKPASS=$SCRIPT_DIR/askpass.sh
chmod +x $SCRIPT_DIR/askpass.sh
sudo --askpass mv /etc/sudoers.d/always-ask-password /etc/sudoers.d/always-ask-password.bak
sudo --askpass mkdir --parents /media/$USER/TailsData
for (( i=1 ; i<=$5 ; i++ )); do
	unset change
	zenity --title="Clone Tails $i of $5" --info --width=300 --text='Plug the new USB stick in the computer.\nAll the data on this USB stick will be lost.' &
	until [ "$change" ]; do
		lsblk --noheadings --paths --raw --nodeps --output NAME > last
		sleep 0.2
		lsblk --noheadings --paths --raw --nodeps --output NAME > now
		change="$(diff --suppress-common-lines last now)"
	done
	kill %
	device=$(echo $change | cut -d' ' -f3)
	sudo --askpass dd if=$RUNNING_DEVICE of=$device bs=4096 count=2359296 status=progress
	#TODO reduce the count to the minimum needed for tails to function, this is 9GiB but it should be 8GiB plus a couple MB
	add_persistence "$1" $2 $3 "$4" $device
	sudo cryptsetup close TailsData_unlocked
	eject $device
	udisksctl power-off --block-device $device
done
# Adds persistence to the running Tails if TailsData is not unlocked or there is no persistence.
if [ test -d /live/persistence/TailsData_unlocked/ ]; then
	echo "Exiting, persistence already exists on running Tails."
	exit 0
fi
sudo mkdir --parents /live/persistence/TailsData_unlocked
add_persistence "$1" $2 $3 "$4" $RUNNING_DEVICE
#udisksctl unmount --block-device=/dev/mapper/TailsData_unlocked
sudo mount --bind /dev/mapper/TailsData_unlocked /live/persistence/TailsData_unlocked/
mkdir $HOME/Persistent
sudo mount /live/persistence/TailsData_unlocked/Persistent $HOME/Persistent	# mounts the ~/Persistent folder
sudo mv /etc/sudoers.d/always-ask-password.bak /etc/sudoers.d/always-ask-password
