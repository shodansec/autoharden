#!/usr/bin/bash

# Filesystem Permisions
chmod -R 700 /root
chmod 700 /boot

# Build Tools
apt install -y build-essential git-crypt automake libtool m4 mlocate net-tools ssh
systemctl enable --now ssh

./setup_github_access.sh

# Network Security
ufw enable
ufw default deny incoming
ufw reload

cd /tmp
git clone https://github.com/hectorm/hblock
cd hblock
make install
cd /tmp
rm -rf hblock
hblock
echo "59 * * * * /usr/local/bin/hblock" >> /var/spool/cron/crontabs/root
cd /root/autoharden

# Malware Scanners
apt install -y chkrootkit rkhunter lynis checksec
rkhunter --propupd

# Virtualization
apt install -y virt-manager
systemctl enable --now libvirtd
echo "Enter the name of the non-root admin user: "
read username

usermod -aG libvirt $username

# Remove unnecessary packages
apt remove -y avahi-daemon cups cups-browsed

# Yubikey
apt-get install libpam-u2f -y

# Kernel Security
cat /root/autoharden/sysctl.d/sysctl-baseline.conf >> /etc/sysctl.conf
sysctl -p

echo "Will you be using a vpn on this host? (y/n): "
read use_vpn

if [ $use_vpn = "n" ]; then
	cat /root/autoharden/sysctl.d/network.conf >> /etc/sysctl.conf
fi

echo "Enter the desired value kernel.yama.ptrace_scope. Use 3 if you do not require debugging, or select 1 if you require debuggin tools (such as gdb): "
read ptrace_scope
echo "kernel.yama.ptrace_scope=$ptrace_scope" >> /etc/sysctl.conf

sysctl -p


# Apparmor
apt install -y apparmor-profiles apparmor-profiles-extra
apt install -y libpam-apparmor dh-apparmor apparmor-utils apparmor-notify apparmor-easyprof
systemctl enable --now apparmor
echo "session optional     pam_apparmor.so order=user,group,default" >> /etc/pam.d/su
cp -r /root/autoharden/apparmor/* /etc/apparmor.d/
apparmor_parser -r -T -W /etc/apparmor.d/pam_binaries /etc/apparmor.d/pam_roles

# Hardened Firefox user.js
echo "Enter the name of the user to install a hardened user.js for firefox for: "
read username

wget -O /home/$username/user.js https://raw.githubusercontent.com/arkenfox/user.js/master/user.js
chown $username:$username /home/$username/user.js
cp /home/$username/user.js /home/$username/.mozilla/firefox/*.default
mv /home/$username/user.js /home/$username/.mozilla/firefox/*.default-release
cd /root/autoharden

# Add Whonix Repo
wget https://www.whonix.org/patrick.asc
chmod -R 700 /root
apt-key --keyring /etc/apt/trusted.gpg.d/whonix.gpg add $(pwd)/patrick.asc
echo "deb https://deb.whonix.org bullseye main contrib non-free" | tee /etc/apt/sources.list.d/whonix.list
apt-get update

# Add Kicksecure Repo
wget https://www.kicksecure.com/derivative.asc
cp derivative.asc /usr/share/keyrings/derivative.asc
echo "deb [signed-by=/usr/share/keyrings/derivative.asc] https://deb.kicksecure.com bullseye main contrib non-free" | tee /etc/apt/sources.list.d/derivative.list
apt update

# security-misc
#apt install --no-install-recommends security-misc

# LKRG
echo "Would you like to install lkrg? (y/n): "
read install_lkrg

if [ $install_lkrg = "y" ]; then
	apt install lkrg-dkms linux-headers-$(uname -r)
	cat /root/autoharden/sysctl.d/lkrg-sysctl.conf >> /etc/sysctl.conf
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

# Entropy
apt install -y jitterentropy-rngd
systemctl enable --now jitterentropy-rngd

apt install -y tpm2-tools tpm2-initramfs-tool libtss2-tcti-tabrmd0 libtss2-tcti-tabrmd-dev libtss2-esys0 libtss2-dev

apt install -y tpm2-abrmd
systemctl stop tpm2-abrmd

tpm2_getrandom --hex 16

cd /tmp

apt install -y build-essential automake libtool m4 libcurl4-gnutls-dev libxml2-dev
apt install -y libjansson-dev libp11-dev librtlsdr-dev

wget https://github.com/nhorman/rng-tools/archive/refs/tags/v6.15.zip
unzip v6.15.zip
cd rng-tools-6.15
./autogen.sh
./configure
make -j8
make install
find $(pwd) -name rngd.service -type f -exec sed -i 's/ExecStart=\/usr\/sbin\/rngd \-f/ExecStart=\/usr\/local\/sbin\/rngd \-r 1 \-r 2 \-r 0 \-W 4096/g' {} +
cp rngd.service /etc/systemd/system
systemctl enable --now rngd

cd /tmp
rm -rf rng-tools-6.15

# Install swtpm
apt install -y build-essential git-crypt
apt-get -y install automake autoconf libtool gcc build-essential libssl-dev dh-exec pkg-config dh-autoreconf

git clone https://github.com/stefanberger/libtpms
cd libtpms
./autogen.sh --with-openssl --prefix=/usr --with-tpm2

make -j8
make check
make install
cd /tmp
rm -rf libtpms

git clone https://github.com/stefanberger/swtpm
cd swtpm

apt-get install -y dh-autoreconf libssl-dev libtasn1-6-dev pkg-config
apt install -y net-tools iproute2 libjson-glib-dev
apt install libgnutls28-dev expect gawk socat libseccomp-dev make -y
apt-get -y install dpkg-dev debhelper libssl-dev libtool net-tools libfuse-dev libglib2.0-dev libgmp-dev expect libtasn1-dev socat python3-twisted gnutls-dev gnutls-bin  libjson-glib-dev python3-setuptools softhsm2 libseccomp-dev gawk

./autogen.sh --with-openssl --prefix=/usr --libdir=/lib64
make -j8
make -j8 check
make install
cd /tmp
rm -rf swtpm-0.7.0

chmod -R 700 /root


# Custom Secure Boot Key
cd /root/autoharden/secureboot
apt install -y efivar efitools

# Backup original secure boot keys and certs etc:
efi-readvar -v PK -o PK.old.esl
efi-readvar -v KEK -o KEK.old.esl
efi-readvar -v db -o db.old.esl
efi-readvar -v dbx -o dbx.old.esl

./mkkeys.sh
mokutil --import DB.cer
./sign-efi.sh /usr/share/efitools/efi/KeyTool.efi
cp /usr/share/efitools/efi/KeyTool.efi /boot/efi/EFI/BOOT/
cp /usr/share/efitools/efi/KeyTool.efi /boot/efi/EFI/ubuntu/
./sign-efi.sh /boot/efi/EFI/BOOT/BOOTX64.EFI
./sign-efi.sh /boot/efi/EFI/BOOT/fbx64.efi
./sign-efi.sh /boot/efi/EFI/BOOT/mmx64.efi
./sign-efi.sh /boot/efi/EFI/ubuntu/grubx64.efi
./sign-efi.sh /boot/efi/EFI/ubuntu/mmx64.efi
./sign-efi.sh /boot/efi/EFI/ubuntu/shimx64.efi
./sign-efi.sh /boot/grub/x86_64-efi/core.efi
./sign-efi.sh /boot/grub/x86_64-efi/grub.efi
./sign-efi.sh /boot/vmlinuz.old
./sign-efi.sh /boot/vmlinuz-5.13.0-30-generic
./sign-efi.sh /boot/vmlinuz
./sign-efi.sh /boot/vmlinuz-5.11.0-27-generic
cp *.cer /boot/efi/EFI/ubuntu
cp *.auth /boot/efi/EFI/ubuntu
cp *.esl /boot/efi/EFI/ubuntu
cp *.crt /boot/efi/EFI/ubuntu
cp *.key /boot/efi/EFI/ubuntu
cp *.txt /boot/efi/EFI/ubuntu

cp *.cer /boot/efi/EFI/BOOT
cp *.auth /boot/efi/EFI/BOOT
cp *.esl /boot/efi/EFI/BOOT
cp *.crt /boot/efi/EFI/BOOT
cp *.key /boot/efi/EFI/BOOT
cp *.txt /boot/efi/EFI/BOOT

# Filesystem and Integrity Monitoring
apt install -y sxid
find /etc -name sxid.conf -type f -exec sed -i 's/ALWAYS_NOTIFY = "no"/ALWAYS_NOTIFY = "yes"/g' {} +
find /etc -name sxid.conf -type f -exec sed -i 's/LISTALL = "no"/LISTALL = "yes"/g' {} +

touch /var/spool/cron/crontabs/root
echo "0 */1 * * * /usr/bin/sxid --spotcheck -l" >> /var/spool/cron/crontabs/root

echo "Would you like to aide? (y/n): "
read install_aide

if [ $install_aide = "y" ]; then
	apt install aide -y
	aideinit
	cp /var/lib/aide/aide.db{.new,}
	update-aide.conf
	cp /var/lib/aide/aide.conf.autogenerated /etc/aide/aide.conf
	echo "*/30 * * * * /usr/bin/aide -c /etc/aide/aide.conf -C" >> /var/spool/cron/crontabs/root
	echo "!/home/" >> /etc/aide/aide.conf
	echo "!/proc/" >> /etc/aide/aide.conf
	echo "!/media/" >> /etc/aide/aide.conf
fi
