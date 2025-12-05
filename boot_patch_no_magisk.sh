SIZE_LIMIT=$((35*1024*1024))
if [ -n "$1" ]; then
    FILE_SIZE=$(($1 * 1024 * 1024))
else
    FILE_SIZE=$(stat -c%s boot.img)
fi

# Flags
export KEEPVERITY=true
export KEEPFORCEENCRYPT=true
export RECOVERYMODE=false
export PREINITDEVICE=cache

#########
# Unpack
#########

chmod -R 755 .

CHROMEOS=false

echo "Unpacking boot image"
../magiskboot unpack boot.img

case $? in
  0 ) ;;
  1 )
    echo "Unsupported/Unknown image format"
    ;;
  2 )
    echo "ChromeOS boot image detected"
    ;;
  * )
    echo "Unable to unpack boot image"
    ;;
esac

###################
# Ramdisk Restores
###################

# Test patch status and do restore
echo "Checking ramdisk status"
if [ -e ramdisk.cpio ]; then
  ../magiskboot cpio ramdisk.cpio test
  STATUS=$?
  SKIP_BACKUP=""
else
  # Stock A only legacy SAR, or some Android 13 GKIs
  cp ../main/ramdisk.cpio ramdisk.cpio
  RECOVERYMODE=true
  STATUS=0
  SKIP_BACKUP="#"
fi
case $((STATUS & 3)) in
  0 )  # Stock boot
    echo "Stock boot image detected"
    SHA1=$(../magiskboot sha1 boot.img)
    cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
    ;;
  1 )  # Magisk patched
    echo "Magisk patched boot image detected"
    ../magiskboot cpio ramdisk.cpio restore
    cp -af ramdisk.cpio ramdisk.cpio.orig 2>/dev/null
    ;;
  2 )  # Unsupported
    echo "Boot image patched by unsupported programs"
    echo "Please restore back to stock boot image"
    ;;
esac

##################
# Ramdisk Patches
##################

echo "- Patching ramdisk"
mkdir cpiotmp
cd cpiotmp
sudo busybox cpio -idv < ../ramdisk.cpio
cd ..
if [ ! -f "cpiotmp/prop.default" ]; then
    cpu_abi="arm64-v8a"
else
    cpu_abi=$(grep -o 'ro.product.cpu.abi=[^ ]*' cpiotmp/prop.default | cut -d '=' -f 2)
    if [ "$cpu_abi" != "arm64-v8a" ]; then
        cpu_abi="armeabi-v7a"
    fi
fi
echo "cpu_abi: $cpu_abi"

echo "KEEPVERITY=$KEEPVERITY" >> config
echo "KEEPFORCEENCRYPT=$KEEPFORCEENCRYPT" >> config
echo "RECOVERYMODE=$RECOVERYMODE" >> config
echo "PREINITDEVICE=$PREINITDEVICE" >> config
[ ! -z $SHA1 ] && echo "SHA1=$SHA1" >> config

../magiskboot cpio ramdisk.cpio \

"$SKIP_BACKUP backup ramdisk.cpio.orig" \


if [ -f kernel ]; then
  # If the kernel doesn't need to be patched at all,
  # keep raw kernel to avoid bootloops on some weird devices
  $PATCHEDKERNEL || rm -f kernel
fi

#################
# Repack & Flash
#################

echo "- Repacking boot image"
if [ "$SKIP_BACKUP" = "#" ]; then
    ../magiskboot compress ramdisk.cpio ramdisk.cpio.gz
    rm ramdisk.cpio
    mv ramdisk.cpio.gz ramdisk.cpio
    ../magiskboot repack -n boot.img patched.img || echo "! Unable to repack boot image"
else
    ../magiskboot repack boot.img patched.img || echo "! Unable to repack boot image"
fi
