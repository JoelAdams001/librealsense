#!/bin/bash

#This script is almost an exact copy of the patch-realsense-ubuntu-lts.sh script, tested on 4.14.47-132.
#There only two small additions / checks. Actually, this script also works for normal ubuntu-lts

#Break execution on any error received
set -e

#Locally suppress stderr to avoid raising not relevant messages
exec 3>&2
exec 2> /dev/null
con_dev=$(ls /dev/video* | wc -l)
exec 2>&3

if [ $con_dev -ne 0 ];
then
	echo -e "\e[32m"
	read -p "Remove all RealSense cameras attached. Hit any key when ready"
	echo -e "\e[0m"
fi

#Include usability functions
source ./scripts/patch-utils.sh

# Get the required tools and headers to build the kernel
#sudo apt-get install linux-headers-generic build-essential git
sudo apt-get install build-essential git

#Packages to build the patched modules
require_package libusb-1.0-0-dev
require_package libssl-dev

retpoline_retrofit=0

LINUX_BRANCH=$(uname -r)
PLATFORM=$(uname -n)
#if [ "$PLATFORM" = "odroid" ]; then
#	#kernel_branch="hwe"
#	#kernel_branch=$LINUX_BRANCH
#	kernel_branch="master"
#else
#	kernel_branch=$(choose_kernel_branch $LINUX_BRANCH)	
#fi
kernel_branch="master"
echo "Kernel branch: " $kernel_branch
# Construct branch name from distribution codename {xenial,bionic,..} and kernel version
#ubuntu_codename=`. /etc/os-release; echo ${UBUNTU_CODENAME/*, /}`
#if [ -z "$UBUNTU_CODENAME" ];
#then
	# Trusty Tahr shall use xenial code base
#	ubuntu_codename="xenial"
#	retpoline_retrofit=1
#fi
ubuntu_codename="bionic"

#kernel_name="ubuntu-${ubuntu_codename}-$kernel_branch"
kernel_name="odroid_bionic"

#Distribution-specific packages
if [ ${ubuntu_codename} == "bionic" ];
then
	require_package libelf-dev
	require_package elfutils
fi


# Get the linux kernel and change into source tree
[ ! -d ${kernel_name} ] && git clone --depth 1 https://github.com/hardkernel/linux -b odroidxu4-4.14.y ./${kernel_name}
cd ${kernel_name}

# Verify that there are no trailing changes., warn the user to make corrective action if needed
if [ $(git status | grep 'modified:' | wc -l) -ne 0 ];
then
	echo -e "\e[36mThe kernel has modified files:\e[0m"
	git status | grep 'modified:'
	echo -e "\e[36mProceeding will reset all local kernel changes. Press 'n' within 10 seconds to abort the operation"
	set +e
	read -n 1 -t 10 -r -p "Do you want to proceed? [Y/n]" response
	set -e
	response=${response,,}    # tolower
	if [[ $response =~ ^(n|N)$ ]]; 
	then
		echo -e "\e[41mScript has been aborted on user requiest. Please resolve the modified files are rerun\e[0m"
		exit 1
	else
		echo -e "\e[0m"
		echo -e "\e[32mUpdate the folder content with the latest from mainline branch\e[0m"
		#git fetch origin $kernel_branch --depth 1
		git fetch origin odroidxu4-4.14.y --depth 1
		printf "Resetting local changes in %s folder\n " ${kernel_name}
		#git reset --hard $kernel_branch
        git reset --hard odroidxu4-4.14.y
	fi
fi

pwd

#Check if we need to apply patches or get reload stock drivers (Developers' option)
[ "$#" -ne 0 -a "$1" == "reset" ] && reset_driver=1 || reset_driver=0

if [ $reset_driver -eq 1 ];
then 
	echo -e "\e[43mUser requested to rebuild and reinstall ubuntu-${ubuntu_codename} stock drivers\e[0m"
else
	# Patching kernel for RealSense devices
	echo -e "\e[32mApplying realsense-uvc patch\e[0m"
	patch -p1 < ../scripts/realsense-camera-formats_ubuntu-${ubuntu_codename}-${kernel_branch}.patch
	echo -e "\e[32mApplying realsense-metadata patch\e[0m"
	patch -p1 < ../scripts/realsense-metadata-ubuntu-${ubuntu_codename}-${kernel_branch}.patch
	echo -e "\e[32mApplying realsense-hid patch\e[0m"
	patch -p1 < ../scripts/realsense-hid-ubuntu-${ubuntu_codename}-${kernel_branch}.patch
	echo -e "\e[32mApplying realsense-powerlinefrequency-fix patch\e[0m"
	patch -p1 < ../scripts/realsense-powerlinefrequency-control-fix.patch
fi


sudo make odroidxu4_defconfig

scripts/config --file .config \
        --enable IIO_BUFFER \
        --module IIO_KFIFO_BUF \
        --module IIO_TRIGGERED_BUFFER \
        --enable IIO_TRIGGER \
        --set-val IIO_CONSUMERS_PER_TRIGGER 2 \
        --module HID_SENSOR_IIO_COMMON \
        --module HID_SENSOR_IIO_TRIGGER \
        --module HID_SENSOR_HUB \
        --module HID_SENSOR_ACCEL_3D \
        --module HID_SENSOR_GYRO_3D

# Build the modules
sudo make modules_prepare
sudo make -j8

sudo make modules_install
sudo cp -f arch/arm/boot/zImage /media/boot
sudo cp -f arch/arm/boot/dts/exynos5422-odroidxu3.dtb /media/boot
sudo cp -f arch/arm/boot/dts/exynos5422-odroidxu4.dtb /media/boot
sudo cp -f arch/arm/boot/dts/exynos5422-odroidxu3-lite.dtb /media/boot
sudo sync

echo -e "\e[32mPatched kernels modules were created successfully\n\e[0m"

echo -e "\e[92m\n\e[1mScript has completed. Please consult the installation guide for further instruction.\n\e[0m"

