#!/bin/sh
clear

LANG=C

# What you need installed to compile
# gcc, gpp, cpp, c++, g++, lzma, lzop, ia32-libs flex

# What you need to make configuration easier by using xconfig
# qt4-dev, qmake-qt4, pkg-config

# Setting the toolchain
# the kernel/Makefile CROSS_COMPILE variable to match the download location of the
# bin/ folder of your toolchain
# toolchain already axist and set! in kernel git. ../aarch64-linux-android-4.9/bin/

# Structure for building and using this script

#--project/				(progect container folder)
#------Ramdisk-Gemini/			(ramdisk files for boot.img)
#------Ramdisk-Gemini-tmp/		(ramdisk tmp store without .git)
#--------lib/modules/			(modules dir, will be added to system on boot)
#------B--B-Kernel/			(kernel source goes here)
#--------READY-RELEASES/		(When using all selector, all models ready kernels will go to this folder)
#--------B--B/				(output directory, where the final boot.img is placed)
#----------meta-inf/			(meta-inf folder for your flashable zip)
#----------system/

# location
KERNELDIR=$(readlink -f .);

# Some variables
VER=jw
export LOCALVERSION=~`echo $VER`
export KBUILD_BUILD_USER=phil
export KBUILD_BUILD_HOST=JDCNRescueParty

CLEANUP()
{
	# begin by ensuring the required directory structure is complete, and empty
	echo "Initialising................."
	rm -rf "$KERNELDIR"/B--B/boot
	rm -f "$KERNELDIR"/B--B/system/lib/modules/*;
	rm -f "$KERNELDIR"/B--B/*.zip
	rm -f "$KERNELDIR"/B--B/*.img
	mkdir -p "$KERNELDIR"/B--B/boot

	if [ -d ../Ramdisk-Gemini-tmp ]; then
		rm -rf ../Ramdisk-Gemini-tmp/*
	else
		mkdir ../Ramdisk-Gemini-tmp
		chown root:root ../Ramdisk-Gemini-tmp
		chmod 777 ../Ramdisk-Gemini-tmp
	fi;

	# force regeneration of .dtb and Image files for every compile
	rm -f arch/arm64/boot/*.dtb
	rm -f arch/arm64/boot/dts/*.dtb
	rm -f arch/arm64/boot/*.cmd
	rm -f arch/arm64/boot/zImage
	rm -f arch/arm64/boot/Image
	rm -f arch/arm64/boot/Image.gz
	rm -f arch/arm64/boot/Image.lz4
	rm -f arch/arm64/boot/Image.gz-dtb
	rm -f arch/arm64/boot/Image.lz4-dtb

	BUILD_MI5=0
}
CLEANUP;

BUILD_NOW()
{
	PYTHON_CHECK=$(ls -la /usr/bin/python | grep python3 | wc -l);
	PYTHON_WAS_3=0;

	if [ "$PYTHON_CHECK" -eq "1" ] && [ -e /usr/bin/python2 ]; then
		if [ -e /usr/bin/python2 ]; then
			rm /usr/bin/python
			ln -s /usr/bin/python2 /usr/bin/python
			echo "Switched to Python2 for building kernel will switch back when done";
			PYTHON_WAS_3=1;
		else
			echo "You need Python2 to build this kernel. install and come back."
			exit 1;
		fi;
	else
		echo "Python2 is used! all good, building!";
	fi;

	# move into the kernel directory and compile the main image
	echo "Compiling Kernel.............";
	if [ ! -f "$KERNELDIR"/.config ]; then
		if [ "$BUILD_MI5" -eq "1" ]; then
			cp arch/arm64/configs/b--b_defconfig .config
		fi;
	fi;

	# get version from config
	GETVER=$(cat "$KERNELDIR/VERSION")

	cp "$KERNELDIR"/.config "$KERNELDIR"/arch/arm64/configs/"$KERNEL_CONFIG_FILE";

	# remove all old modules before compile
	for i in $(find "$KERNELDIR"/ -name "*.ko"); do
		rm -f "$i";
	done;

	# Idea by savoca
	NR_CPUS=$(grep -c ^processor /proc/cpuinfo)

	if [ "$NR_CPUS" -le "2" ]; then
		NR_CPUS=4;
		echo "Building kernel with 4 CPU threads";
	else
		echo "Building kernel with $NR_CPUS CPU threads";
	fi;

	# build Image
	# time make ARCH=arm64 CROSS_COMPILE=gcc-linaro-7.3.1/bin/aarch64-linux-gnu- -j ${NR_CPUS}
	time make ARCH=arm64 CROSS_COMPILE=aarch64--glibc--stable-2018.02-2/bin/aarch64-buildroot-linux-gnu- -j ${NR_CPUS}

	cp "$KERNELDIR"/.config "$KERNELDIR"/arch/arm64/configs/"$KERNEL_CONFIG_FILE";

	stat "$KERNELDIR"/arch/arm64/boot/Image.gz-dtb || exit 1;

	# compile the modules, and depmod to create the final Image
	echo "Compiling Modules............"
	# time make ARCH=arm64 CROSS_COMPILE=gcc-linaro-7.3.1/bin/aarch64-linux-gnu- modules -j ${NR_CPUS} || exit 1
	time make ARCH=arm64 CROSS_COMPILE=aarch64--glibc--stable-2018.02-2/bin/aarch64-buildroot-linux-gnu- modules -j ${NR_CPUS} || exit 1

	# move the compiled Image and modules into the B--B working directory
	echo "Move compiled objects........"

	# copy needed branch files to Ramdisk temp dir.
	cp -a ../Ramdisk-Gemini/* ../Ramdisk-Gemini-tmp/

	if [ ! -d "$KERNELDIR"/B--B/system/lib/modules ]; then
		mkdir -p "$KERNELDIR"/B--B/system/lib/modules;
	fi;

	for i in $(find "$KERNELDIR" -name '*.ko'); do
		cp -av "$i" "$KERNELDIR"/B--B/system/lib/modules/;
	done;

	chmod 755 "$KERNELDIR"/B--B/system/lib/modules/*

	# remove empty directory placeholders from tmp-initramfs
	for i in $(find ../Ramdisk-Gemini-tmp/ -name EMPTY_DIRECTORY); do
		rm -f "$i";
	done;

	if [ -e "$KERNELDIR"/arch/arm64/boot/Image ]; then

		if [ ! -d B--B/boot ]; then
			mkdir B--B/boot
		fi;

		cp arch/arm64/boot/Image.gz-dtb B--B/boot/
		cp .config B--B/view_only_config

		# strip not needed debugs from modules.
		# gcc-linaro-7.3.1/bin/aarch64-linux-gnu-strip --strip-unneeded "$KERNELDIR"/B--B/system/lib/modules/* 2>/dev/null
		# gcc-linaro-7.3.1/bin/aarch64-linux-gnu-strip --strip-debug "$KERNELDIR"/B--B/system/lib/modules/* 2>/dev/null
		aarch64--glibc--stable-2018.02-2/bin/aarch64-buildroot-linux-gnu-strip --strip-unneeded "$KERNELDIR"/B--B/system/lib/modules/* 2>/dev/null
		aarch64--glibc--stable-2018.02-2/bin/aarch64-buildroot-linux-gnu-strip --strip-debug "$KERNELDIR"/B--B/system/lib/modules/* 2>/dev/null

		# create the Ramdisk and move it to the output working directory
		echo "Create Ramdisk..............."
		scripts/mkbootfs ../Ramdisk-Gemini-tmp | gzip > ramdisk.gz 2>/dev/null
		mv ramdisk.gz B--B/boot/

		if [ "$PYTHON_WAS_3" -eq "1" ]; then
			rm /usr/bin/python
			ln -s /usr/bin/python3 /usr/bin/python
		fi;

		# add kernel config to kernel zip for other devs
		cp "$KERNELDIR"/.config B--B/

		# build the final boot.img ready for inclusion in flashable zip
		echo "Build boot.img..............."
		cp scripts/mkbootimg B--B/boot/
		cd B--B/boot/
		base=0x80000000
		kernel_offset=0x80008000
		ramdisk_offset=0x01000000
		second_offset=0x80f00000
		tags_addr=0x00000100
		pagesize=4096
		cmd_line="androidboot.hardware=qcom ehci-hcd.park=3 lpm_levels.sleep_disabled=1 cma=32M@0-0xffffffff androidboot.selinux=permissive"
		#./mkbootimg --kernel Image --ramdisk ramdisk.gz --cmdline "$cmd_line" --base $base --pagesize $pagesize --kernel_offset $kernel_offset --ramdisk_offset $ramdisk_offset --second_offset $second_offset --tags_offset $tags_addr -o newboot.img
		./mkbootimg --kernel Image.gz-dtb --ramdisk ramdisk.gz --base $base --cmdline "$cmd_line" --pagesize $pagesize --kernel_offset $kernel_offset --ramdisk_offset $ramdisk_offset --tags_offset $tags_addr -o newboot.img
		mv newboot.img ../boot.img

		# cleanup all temporary working files
		echo "Post build cleanup..........."
		cd ..
		rm -rf boot

		cd "$KERNELDIR"/B--B/

		# create the flashable zip file from the contents of the output directory
		echo "Make flashable zip..........."
		zip -r B--B-Kernel-"${GETVER}"-N-"$(date +"[%H-%M]-[%d-%m]-Mi5-PWR-CORE")".zip * >/dev/null
		stat boot.img
		rm -f ./*.img
		cd ..
	else
		if [ "$PYTHON_WAS_3" -eq "1" ]; then
			rm /usr/bin/python
			ln -s /usr/bin/python3 /usr/bin/python
		fi;

		# with red-color
		echo -e "\e[1;31mKernel STUCK in BUILD! no Image exist\e[m"
	fi;
}

CLEAN_KERNEL()
{
	PYTHON_CHECK=$(ls -la /usr/bin/python | grep python3 | wc -l);
	CLEAN_PYTHON_WAS_3=0;

	if [ "$PYTHON_CHECK" -eq "1" ] && [ -e /usr/bin/python2 ]; then
		if [ -e /usr/bin/python2 ]; then
			rm /usr/bin/python
			ln -s /usr/bin/python2 /usr/bin/python
			echo "Switched to Python2 for building kernel will switch back when done";
			CLEAN_PYTHON_WAS_3=1;
		else
			echo "You need Python2 to build this kernel. install and come back."
			exit 1;
		fi;
	else
		echo "Python2 is used! all good, building!";
	fi;

	if [ -e .config ]; then
		cp -pv .config .config.bkp;
	elif [ -e .config.bkp ]; then
		rm .config.bkp
	fi;
	make ARCH=arm64 mrproper;
	make clean;
	if [ -e .config.bkp ]; then
		cp -pv .config.bkp .config;
	fi;

	if [ "$CLEAN_PYTHON_WAS_3" -eq "1" ]; then
		rm /usr/bin/python
		ln -s /usr/bin/python3 /usr/bin/python
	fi;

	# restore firmware libs*.a
	git checkout firmware/
}

export KERNEL_CONFIG=b--b_defconfig
KERNEL_CONFIG_FILE=b--b_defconfig
BUILD_MI5=1;
BUILD_NOW;
