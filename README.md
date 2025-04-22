
————————————————————
GRUB Repair Utility
————————————————————
A comprehensive utility for diagnosing and repairing Linux boot issues related to the GRUB bootloader.


——————————
Overview
——————————

This script helps troubleshoot and fix common boot problems on Linux systems by checking and repairing key components of the boot process:

  - GRUB bootloader configuration
  - Kernel availability
  - Initramfs/initrd files
  - Boot partition settings

It provides a guided, interactive process to safely repair your system when it fails to boot properly.


—————————————————————————
Supported Distributions
—————————————————————————
  - Red Hat Enterprise Linux
  - CentOS
  - Rocky Linux
  - AlmaLinux
  - Ubuntu
  - Debian
  - SUSE Linux
  - Amazon Linux


————————————————————
Step-by-Step Process
————————————————————
  1. The script will display available storage devices
  2. Select the root partition of your non-booting system
  3. If you have a separate boot partition, specify it when prompted
  4. The script will identify your Linux distribution
  5. It will analyze your boot configuration for issues
  6. If problems are found, you'll be given repair options
  7. Choose whether to repair the identified issues
  8. The script will generate a summary report when finished


—————————————
Safety Features
—————————————
  - Creates backups of your /boot directory before making changes
  - Checks for prerequisites before executing repairs
  - Verifies repairs after they are completed
  - Uses color-coded output to highlight important information
  - Safely unmounts all partitions when finished


—————————————
Common Scenarios
—————————————

>>  Missing GRUB Configuration

  If your system has a missing or corrupted GRUB configuration, this script will detect it and offer to:
  - Reinstall GRUB to the disk
  - Generate a new configuration file

>> Missing or Corrupt Initramfs

  If your initramfs files are missing or don't match your kernels, the script can:
  - Identify which kernels are missing initramfs files
  - Rebuild the initramfs files for existing kernels

>> No Bootable Kernel Found

  If your system is missing kernels, the script can:
  - Install a new kernel package appropriate for your distribution
  - Generate the required initramfs for the new kernel


——————
Execution
——————
# For RHEL/CentOS/Fedora
	sudo dnf install git
# or
	sudo yum install git

git clone https://github.com/nkshirsa-aws/grub-repair.git
cd grub-repair
chmod +x grub-repair.sh
sudo ./grub-repair.sh



———————————
Contribution
———————————
Feel free to submit issues or pull requests to improve this utility. Contributions are welcome!

