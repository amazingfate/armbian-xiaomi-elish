#!/bin/bash
set -ex
image_name=$1
efi_start_sector=$(gdisk -l ./${image_name}|grep efi|awk '{print $2}')
efi_end_sector=$(gdisk -l ./${image_name}|grep efi|awk '{print $3}')
rootfs_start_sector=$(gdisk -l ./${image_name}|grep rootfs|awk '{print $2}')
rootfs_end_sector=$(gdisk -l ./${image_name}|grep rootfs|awk '{print $3}')
rm esp*.img rootfs*.img ||true
dd if=./${image_name} skip=${efi_start_sector} count=$((${efi_end_sector} - ${efi_start_sector})) of=esp.img
dd if=./${image_name} skip=${rootfs_start_sector} count=$((${rootfs_end_sector} - ${rootfs_start_sector})) of=rootfs.img
rm ${image_name}

old_rootfs_image=rootfs.img
old_rootfs_image_mount_dir=rootfs
old_rootfs_image_uuid=$(blkid -s UUID -o value ${old_rootfs_image})
old_esp_image=esp.img
old_esp_image_mount_dir=esp
old_esp_image_uuid=$(blkid -s UUID -o value ${old_esp_image})
new_rootfs_image=${image_name%*.img}-rootfs.img
new_rootfs_image_mount_dir=rootfs-new
new_esp_image=${image_name%*.img}-esp.img
new_esp_image_mount_dir=esp-new
mkdir -p ${old_rootfs_image_mount_dir} ${old_esp_image_mount_dir} ${new_rootfs_image_mount_dir} ${new_esp_image_mount_dir}
truncate --size=8192M ${new_rootfs_image}
truncate --size=200M ${new_esp_image}
mkfs.fat -S 4096 ${new_esp_image}
mkfs.ext4 -F ${new_rootfs_image}
new_esp_image_uuid=$(blkid -s UUID -o value ${new_esp_image})
new_rootfs_image_uuid=$(blkid -s UUID -o value ${new_rootfs_image})
sudo mount ${old_esp_image} ${old_esp_image_mount_dir}
sudo mount ${new_esp_image} ${new_esp_image_mount_dir}
sudo cp -rfp ${old_esp_image_mount_dir}/* ${new_esp_image_mount_dir}/
sudo umount ${new_esp_image_mount_dir}
sudo umount ${old_esp_image_mount_dir}
sudo mount ${old_rootfs_image} ${old_rootfs_image_mount_dir}
sudo mount ${new_rootfs_image} ${new_rootfs_image_mount_dir}
sudo cp -rfp ${old_rootfs_image_mount_dir}/* ${new_rootfs_image_mount_dir}/
sudo sed -i "s|${old_rootfs_image_uuid}|${new_rootfs_image_uuid}|g" ${new_rootfs_image_mount_dir}/etc/fstab
sudo sed -i "s|${old_esp_image_uuid}|${new_esp_image_uuid}|g" ${new_rootfs_image_mount_dir}/etc/fstab
gzip -c ./${new_rootfs_image_mount_dir}/boot/vmlinuz-*-sm8250-arm64 > Image.gz
for panel_type in boe csot
do
cat Image.gz ./${new_rootfs_image_mount_dir}/usr/lib/linux-image-*-sm8250-arm64/qcom/sm8250-xiaomi-elish-${panel_type}.dtb > Image.gz-dtb-${panel_type}
./mkbootimg.py \
        --kernel Image.gz-dtb-${panel_type} \
        --ramdisk ./${new_rootfs_image_mount_dir}/boot/initrd.img-*-sm8250-arm64 \
        --base 0x0 \
        --second_offset 0x00f00000 \
        --cmdline "root=UUID=${new_rootfs_image_uuid}" \
        --kernel_offset 0x8000 \
        --ramdisk_offset 0x1000000 \
        --tags_offset 0x100 \
        --pagesize 4096 \
        -o armbian-kernel-${panel_type}.img
done
sudo umount ${new_rootfs_image_mount_dir}
sudo umount ${old_rootfs_image_mount_dir}
e2fsck -p -f ${new_rootfs_image}
resize2fs -M ${new_rootfs_image}
xz -z -T0 ${new_rootfs_image}
xz -z -T0 ${new_esp_image}
xz -z -T0 armbian-kernel.img
rm ${old_rootfs_image} ${old_esp_image} ||true
