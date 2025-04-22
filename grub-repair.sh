#################################################################
#
# Script Name: grub_repair.sh
# Description: Automated GRUB repair script for Linux systems
# Author: Nikhil Kshirsagar
# Email: nkshirsa@amazon.com
# Created Date: 10/04/2025
# Last Modified: 19/04/2025
#
# Permission: chmod a+x grub_repair.sh
# Usage: sudo ./grub_repair.sh
#
# Supported Distributions:
# - Red Hat Enterprise Linux
# - CentOS
# - Amazon Linux
# - Ubuntu/Debian
# - SUSE Linux
#
#
#################################################################

#!/bin/bash

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to check if running as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "\n${RED}This script must be run as root${NC}"
        exit 1
    fi
}

# Function to detect and display available devices
show_devices() {
    echo -e "\n${GREEN}Available Devices:${NC}\n"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL
    echo -e "\n${YELLOW}Note: Use the full path of the devices (e.g., /dev/xvdf1, /dev/sda1, /dev/nvme0n1p1)${NC}"
    echo ""
}

# Function to detect Linux distribution from mounted root
detect_distribution() {
    local mount_point=$1
    if [ -f "$mount_point/etc/os-release" ]; then
        source "$mount_point/etc/os-release"
        echo "$NAME $VERSION_ID"
    else
        echo "Unknown Distribution"
    fi
}

# Function to mount partitions
mount_partition() {
    local device=$1
    local mount_point=$2
    local mount_options="rw"

    echo -e "\n${GREEN}Attempting to mount $device to $mount_point${NC}"
    
    if ! mount -o $mount_options $device $mount_point 2>/dev/null; then
        echo -e "${YELLOW}Trying to mount with nouuid option...${NC}"
        if ! mount -o $mount_options,nouuid $device $mount_point; then
            echo -e "\n${RED}Failed to mount $device${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}Successfully mounted $device${NC}"
}

# Function to check GRUB configuration
check_grub_config() {
    local mount_point=$1
    local no_issues=true
    
    echo -e "\n${GREEN}=== System Boot Configuration Status ===${NC}\n"
    
    # Check GRUB files and configurations
    echo -e "${YELLOW}GRUB Status:${NC}"
    if [ -f "$mount_point/boot/grub2/grub.cfg" ]; then
        echo -e "✓ ${GREEN}GRUB2 config found: /boot/grub2/grub.cfg${NC}"
    elif [ -f "$mount_point/boot/grub/grub.cfg" ]; then
        echo -e "✓ ${GREEN}GRUB config found: /boot/grub/grub.cfg${NC}"
    else
        echo -e "✗ ${RED}Missing GRUB configuration file${NC}"
        no_issues=false
    fi

    if [ -d "$mount_point/boot/grub2" ]; then
        echo -e "✓ ${GREEN}GRUB2 modules directory exists${NC}"
    elif [ -d "$mount_point/boot/grub" ]; then
        echo -e "✓ ${GREEN}GRUB modules directory exists${NC}"
    else
        echo -e "✗ ${RED}Missing GRUB modules directory${NC}"
        no_issues=false
    fi

    # Check Kernel files
    echo -e "\n${YELLOW}Kernel Status:${NC}"
    local kernel_count=0
    mapfile -t KERNEL_FILES < <(find "$mount_point/boot" -type f \( -name "vmlinuz*" -o -name "vmlinux*" \) | sort -V)
    
    if [ ${#KERNEL_FILES[@]} -gt 0 ]; then
        for kernel in "${KERNEL_FILES[@]}"; do
            kernel_base=$(basename "$kernel")
            echo -e "✓ ${GREEN}Found kernel: $kernel_base${NC} ($(du -h "$kernel" | cut -f1))"
            ((kernel_count++))
        done
    else
        echo -e "✗ ${RED}No kernel files found${NC}"
        echo ""
        read -p "Do you want to install a kernel? (y/n): " INSTALL_KERNEL
        if [ "$INSTALL_KERNEL" = "y" ]; then
            install_kernel "$MOUNT_POINT" "$DISTRO"
            if [ $? -eq 0 ]; then
                # Refresh kernel files list after installation
                mapfile -t KERNEL_FILES < <(find "$mount_point/boot" -type f \( -name "vmlinuz*" -o -name "vmlinux*" \) | sort -V)
                echo -e "\n${YELLOW}Updated Kernel Status:${NC}"
                for kernel in "${KERNEL_FILES[@]}"; do
                    kernel_base=$(basename "$kernel")
                    echo -e "✓ ${GREEN}Found kernel: $kernel_base${NC} ($(du -h "$kernel" | cut -f1))"
                    ((kernel_count++))
                done
            fi
        else
            echo -e "\n${YELLOW}Skipping kernel installation${NC}"
        fi
    fi


    # Check initramfs/initrd files
    echo -e "\n${YELLOW}Initramfs/Initrd Status:${NC}"
    for KERNEL in "${KERNEL_FILES[@]}"; do
        KERNEL_BASE=$(basename "$KERNEL")
        KERNEL_VERSION=${KERNEL_BASE#vmlinuz-}
        KERNEL_VERSION=${KERNEL_VERSION#vmlinux-}
        
        local found_initrd=false
        for PATTERN in \
            "$mount_point/boot/initrd.img-$KERNEL_VERSION" \
            "$mount_point/boot/initramfs-$KERNEL_VERSION.img" \
            "$mount_point/boot/initramfs-$KERNEL_VERSION" \
            "$mount_point/boot/initrd-$KERNEL_VERSION.img"
        do
            if [ -f "$PATTERN" ]; then
                echo -e "✓ ${GREEN}Found initramfs: $(basename "$PATTERN")${NC} ($(du -h "$PATTERN" | cut -f1))"
                found_initrd=true
                break
            fi
        done

        if [ "$found_initrd" = false ]; then
            echo -e "✗ ${RED}Missing initramfs for kernel: $KERNEL_BASE${NC}"
            no_issues=false
        fi
    done

    # Summary
    echo -e "\n${YELLOW}Summary:${NC}"
    if [ "$no_issues" = true ]; then
        echo -e "${GREEN}✓ No GRUB issues found${NC}"
        echo -e "${GREEN}✓ Found $kernel_count kernel(s)${NC}"
        echo -e "${GREEN}✓ All kernels have matching initramfs files${NC}"
        return 0
    else
        echo -e "${RED}⚠ Some issues were detected${NC}"
        return 1
    fi
}

# Function to get the correct device name
get_device_name() {
    local root_part=$1
    # Extract the base device name without partition number
    if [[ $root_part == *"xvd"* ]]; then
        echo "${root_part%[0-9]}" # Remove trailing numbers for xvd devices
    elif [[ $root_part == *"nvme"* ]]; then
        echo "${root_part%p[0-9]}" # Remove trailing partition number for NVMe devices
    else
        echo "${root_part:0:-1}" # Remove last character for regular devices
    fi
}

# Function to install kernel
install_kernel() {
    local mount_point=$1
    local distribution=$2

    echo -e "\n${GREEN}Attempting to install kernel...${NC}"

    # Bind necessary filesystems
    mount --bind /dev $mount_point/dev 2>/dev/null || true
    mount --bind /proc $mount_point/proc 2>/dev/null || true
    mount --bind /sys $mount_point/sys 2>/dev/null || true

    case $distribution in
        *"Red Hat"*|*"CentOS"*|*"Rocky"*|*"AlmaLinux"*)
            chroot $mount_point /bin/bash -c "
                dnf install -y kernel kernel-core
            "
            ;;
        *"Amazon"*)
            chroot $mount_point /bin/bash -c "
                yum install -y kernel
            "
            ;;
        *"Ubuntu"*|*"Debian"*)
            chroot $mount_point /bin/bash -c "
                apt-get update
                apt-get install -y linux-image-generic
            "
            ;;
        *"SUSE"*)
            chroot $mount_point /bin/bash -c "
                zypper install -y kernel-default
            "
            ;;
        *)
            echo -e "\n${RED}Unsupported distribution for kernel installation${NC}"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully installed kernel${NC}"
        return 0
    else
        echo -e "${RED}Failed to install kernel${NC}"
        return 1
    fi
}



# Function to rebuild initramfs
rebuild_initramfs() {
    local mount_point=$1
    local distribution=$2
    local kernel_version=$3

    echo -e "\n${GREEN}Attempting to rebuild initramfs for kernel $kernel_version${NC}"

    # Bind necessary filesystems if not already mounted
    mount --bind /dev $mount_point/dev 2>/dev/null || true
    mount --bind /proc $mount_point/proc 2>/dev/null || true
    mount --bind /sys $mount_point/sys 2>/dev/null || true

    case $distribution in
        *"Red Hat"*|*"CentOS"*|*"Rocky"*|*"AlmaLinux"*)
            chroot $mount_point /bin/bash -c "
                if command -v dracut >/dev/null 2>&1; then
                    dracut --force /boot/initramfs-$kernel_version.img $kernel_version
                else
                    echo -e '${RED}dracut not found${NC}'
                    exit 1
                fi
            "
            ;;
        *"Ubuntu"*|*"Debian"*)
            chroot $mount_point /bin/bash -c "
                if command -v update-initramfs >/dev/null 2>&1; then
                    update-initramfs -c -k $kernel_version
                else
                    echo -e '${RED}update-initramfs not found${NC}'
                    exit 1
                fi
            "
            ;;
        *"SUSE"*)
            chroot $mount_point /bin/bash -c "
                if command -v mkinitrd >/dev/null 2>&1; then
                    mkinitrd -k /boot/vmlinuz-$kernel_version -i /boot/initrd-$kernel_version
                else
                    echo -e '${RED}mkinitrd not found${NC}'
                    exit 1
                fi
            "
            ;;
        *)
            echo -e "\n${RED}Unsupported distribution for initramfs rebuild${NC}"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully rebuilt initramfs for kernel $kernel_version${NC}"
        return 0
    else
        echo -e "${RED}Failed to rebuild initramfs${NC}"
        return 1
    fi
}

# Function to repair GRUB
repair_grub() {
    local mount_point=$1
    local distribution=$2
    local root_part=$3

    # Get base device name
    local device=$(get_device_name $root_part)
    
    echo -e "\n${GREEN}Setting up chroot environment...${NC}"
    
    # Bind necessary filesystems
    mount --bind /dev $mount_point/dev || { echo -e "\n${RED}Failed to bind /dev${NC}"; exit 1; }
    mount --bind /proc $mount_point/proc || { echo -e "\n${RED}Failed to bind /proc${NC}"; exit 1; }
    mount --bind /sys $mount_point/sys || { echo -e "\n${RED}Failed to bind /sys${NC}"; exit 1; }

    echo -e "\n${GREEN}Installing GRUB on device: $device${NC}\n"

    # Chroot and repair GRUB
    case $distribution in
        *"Red Hat"*|*"Amazon"*|*"CentOS"*)
            chroot $mount_point /bin/bash -c "
                echo 'Installing GRUB2...'
                [ ! -d /boot/grub2 ] && mkdir -p /boot/grub2
                grub2-install $device
                if [ \$? -eq 0 ]; then
                    echo -e '\nGenerating GRUB2 configuration...'
                    grub2-mkconfig -o /boot/grub2/grub.cfg
                fi
            "
            ;;
        *"Ubuntu"*|*"Debian"*)
            chroot $mount_point /bin/bash -c "
                echo 'Checking GRUB directories...'
                [ ! -d /boot/grub ] && mkdir -p /boot/grub
                echo 'Updating GRUB...'
                update-grub
                if [ \$? -eq 0 ]; then
                    echo -e '\nInstalling GRUB...'
                    grub-install $device
                fi
            "
            ;;
        *"SUSE"*)
            chroot $mount_point /bin/bash -c "
                echo 'Installing GRUB2...'
                [ ! -d /boot/grub2 ] && mkdir -p /boot/grub2
                grub2-install $device
                if [ \$? -eq 0 ]; then
                    echo -e '\nGenerating GRUB2 configuration...'
                    grub2-mkconfig -o /boot/grub2/grub.cfg
                fi
            "
            ;;
        *)
            echo -e "\n${RED}Unsupported distribution${NC}"
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}GRUB installation completed successfully${NC}"
        return 0
    else
        echo -e "\n${RED}GRUB installation failed${NC}"
        return 1
    fi
}

# Function to unmount everything
cleanup() {
    local mount_point=$1
    local repair_chosen=$2
    
    echo -e "\n${YELLOW}Cleaning up mounts...${NC}"
    
    # Function to check if a path is mounted
    is_mounted() {
        mount | grep -q " $1 "
    }

    # Function to force unmount with multiple attempts
    force_unmount() {
        local path=$1
        local retries=3
        local count=0

        while is_mounted "$path" && [ $count -lt $retries ]; do
            # Try to kill processes using the mount
            fuser -k -m "$path" >/dev/null 2>&1
            
            # Wait a moment
            sleep 1
            
            # Try normal unmount first
            umount "$path" 2>/dev/null || \
            # Try lazy unmount if normal unmount fails
            umount -l "$path" 2>/dev/null
            
            ((count++))
            
            # If still mounted, wait a bit before next attempt
            if is_mounted "$path" && [ $count -lt $retries ]; then
                sleep 2
            fi
        done

        if is_mounted "$path"; then
            echo -e "${RED}Warning: Could not unmount $path${NC}"
            echo -e "${YELLOW}You may need to manually unmount it later with: umount -l $path${NC}"
            return 1
        fi
    }

    # List of possible bind mounts to check and unmount
    local bind_mounts=(
        "$mount_point/dev/pts"
        "$mount_point/dev"
        "$mount_point/proc"
        "$mount_point/sys"
    )

    # If repair was chosen, ensure we unmount all bind mounts
    if [ "$repair_chosen" = "y" ]; then
        for bind_mount in "${bind_mounts[@]}"; do
            if is_mounted "$bind_mount"; then
                force_unmount "$bind_mount"
            fi
        done
    fi

    # Unmount /boot if it's mounted
    if is_mounted "$mount_point/boot"; then
        force_unmount "$mount_point/boot"
    fi

    # Finally unmount the root mount point
    if is_mounted "$mount_point"; then
        # Find and kill any remaining processes using the mount
        if pids=$(lsof -t "$mount_point" 2>/dev/null); then
            for pid in $pids; do
                kill -15 $pid 2>/dev/null || kill -9 $pid 2>/dev/null
            done
            sleep 1
        fi

        force_unmount "$mount_point"
    fi

    echo -e "${GREEN}Cleanup completed${NC}"
}

# Function to generate final report
generate_report() {
    local mount_point=$1
    local distribution=$2
    local root_part=$3
    local has_boot=$4
    local boot_part=$5
    local issues=$6
    local repair_chosen=$7

    echo -e "\n${GREEN}=== GRUB Repair Report ===${NC}\n"
    echo "Distribution: $distribution"
    echo "Root Device: $root_part"
    [ "$has_boot" = "y" ] && echo "Boot Device: $boot_part"
    echo -e "\nInitial Issues: $issues"
    echo -e "\nActions Performed:"
    echo "- Mounted root partition"
    [ "$has_boot" = "y" ] && echo "- Mounted boot partition"
    
    if [ "$repair_chosen" = "y" ]; then
        echo "- Installed GRUB bootloader"
        echo "- Generated GRUB configuration"
    else
        echo "- No repairs performed (user chose not to repair)"
    fi
    
    echo "- Cleaned up mounts"
}


# Function to backup boot directory    
backup_boot() {
    local mount_point=$1
    local backup_dir="$mount_point/tmp/boot_backup_$(date +%Y%m%d_%H%M%S)"
    
    echo -e "\n${GREEN}Creating backup of /boot directory...${NC}"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    # Perform the backup
    if cp -a "$mount_point/boot/"* "$backup_dir/" 2>/dev/null; then
        echo -e "${GREEN}Boot directory backup created successfully at: $backup_dir${NC}"
        return 0
    else
        echo -e "${RED}Failed to create boot directory backup${NC}"
        return 1
    fi
}


# Main script
main() {
    check_root
    
    echo -e "\n${GREEN}GRUB Repair Script${NC}"
    show_devices

    # Create mount point
    MOUNT_POINT="/mnt"
    mkdir -p $MOUNT_POINT

    # Get root partition
    read -p "Enter root partition: " ROOT_PART
    mount_partition $ROOT_PART $MOUNT_POINT

    # Check if separate boot partition exists
    echo ""
    read -p "Is there a separate boot partition? (y/n): " HAS_BOOT
    if [ "$HAS_BOOT" = "y" ]; then
        echo ""
        read -p "Enter boot partition: " BOOT_PART
        mkdir -p $MOUNT_POINT/boot
        mount_partition $BOOT_PART $MOUNT_POINT/boot
    fi

    # Add backup call HERE
    backup_boot $MOUNT_POINT

    # Detect distribution
    DISTRO=$(detect_distribution $MOUNT_POINT)
    echo -e "\n${GREEN}Detected Distribution: $DISTRO${NC}"

    # Check kernel and initramfs
    echo -e "\n${GREEN}System files found:${NC}"
    
    # Find kernel files
    mapfile -t KERNEL_FILES < <(find "$MOUNT_POINT/boot" -type f \( -name "vmlinuz*" -o -name "vmlinux*" \) | sort -V)
    
    if [ ${#KERNEL_FILES[@]} -gt 0 ]; then
        for KERNEL in "${KERNEL_FILES[@]}"; do
            KERNEL_BASE=$(basename "$KERNEL")
            # Extract kernel version handling both vmlinuz and vmlinux formats
            KERNEL_VERSION=${KERNEL_BASE#vmlinuz-}
            KERNEL_VERSION=${KERNEL_VERSION#vmlinux-}
            
            echo "- Kernel: $KERNEL_BASE ($(du -h "$KERNEL" | cut -f1))"

            # Look for matching initrd/initramfs with multiple patterns
            FOUND_INITRD=false
            for PATTERN in \
                "$MOUNT_POINT/boot/initrd.img-$KERNEL_VERSION" \
                "$MOUNT_POINT/boot/initramfs-$KERNEL_VERSION.img" \
                "$MOUNT_POINT/boot/initramfs-$KERNEL_VERSION" \
                "$MOUNT_POINT/boot/initrd-$KERNEL_VERSION.img"
            do
                if [ -f "$PATTERN" ]; then
                    echo "  └─ Initrd: $(basename "$PATTERN") ($(du -h "$PATTERN" | cut -f1))"
                    FOUND_INITRD=true
                    break
                fi
            done

            if [ "$FOUND_INITRD" = false ]; then
                echo -e "  └─ ${RED}No matching initramfs/initrd found for this kernel${NC}"
                echo ""
                read -p "Do you want to rebuild initramfs for this kernel? (y/n): " REBUILD_INITRD
                if [ "$REBUILD_INITRD" = "y" ]; then
                    rebuild_initramfs "$MOUNT_POINT" "$DISTRO" "$KERNEL_VERSION"
                fi
            fi
        done
    else
        echo -e "${RED}No kernel files found${NC}"
    fi

    # Check GRUB issues
    check_grub_config $MOUNT_POINT
    GRUB_CHECK_STATUS=$?

    if [ $GRUB_CHECK_STATUS -ne 0 ]; then
        echo ""
        read -p "Do you want to repair the detected issues? (y/n): " REPAIR
        if [ "$REPAIR" = "y" ]; then
            echo -e "\n${GREEN}Repairing GRUB...${NC}"
            repair_grub $MOUNT_POINT "$DISTRO" "$ROOT_PART"
            REPAIR_STATUS=$?
        else
            echo -e "\n${YELLOW}Skipping repairs as per user choice${NC}"
        fi
    fi

    # Cleanup
    cleanup $MOUNT_POINT "$REPAIR"

    # Generate final report
    generate_report "$MOUNT_POINT" "$DISTRO" "$ROOT_PART" "$HAS_BOOT" "$BOOT_PART" "$ISSUES" "$REPAIR"
    
    if [ "$REPAIR" = "y" ]; then
        if [ $REPAIR_STATUS -eq 0 ]; then
            echo -e "\n${GREEN}GRUB repair completed successfully${NC}"
        else
            echo -e "\n${RED}GRUB repair encountered some issues${NC}"
        fi
    fi
    
    echo -e "\n${GREEN}Script completed${NC}\n"
}

# Run main function
main





