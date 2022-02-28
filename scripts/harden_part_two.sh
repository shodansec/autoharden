#!/bin/bash
########################################################################################
# Only run this script after you have configured custom keys for secure boot correctly #
########################################################################################

# Add Whonix Repo
wget https://www.whonix.org/patrick.asc
chmod -R 700 /root
apt-key --keyring /etc/apt/trusted.gpg.d/whonix.gpg add $(pwd)/patrick.asc
echo "deb https://deb.whonix.org bullseye main contrib non-free" | tee /etc/apt/sources.list.d/whonix.list
apt update

# Add Kicksecure Repo
wget https://www.kicksecure.com/derivative.asc
cp derivative.asc /usr/share/keyrings/derivative.asc
echo "deb [signed-by=/usr/share/keyrings/derivative.asc] https://deb.kicksecure.com bullseye main contrib non-free" | tee /etc/apt/sources.list.d/derivative.list
apt update

# LKRG
echo "Would you like to install lkrg? (y/n): "
read install_lkrg

if [ $install_lkrg = "y" ]; then
	apt install lkrg-dkms linux-headers-$(uname -r)
	cat sysctl.d/lkrg-sysctl.conf >> /etc/sysctl.conf
	sysctl -p
fi

# TCP ISN mitigation
echo "Would you like to install tirdad? (y/n): "
read install_tirdad

if [ $install_tirdad = "y" ]; then
	timedatectl set-ntp 0
	systemctl disable systemd-timesyncd.service
	apt install -y tirdad
fi

# Keystroke Fingerprint Resisting
apt install -y kloak
