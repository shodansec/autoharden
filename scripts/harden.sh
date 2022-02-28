#!/bin/bash

# Filesystem Permisions
chmod -R 700 /root
chmod 700 /boot

apt update
apt upgrade -y

# Install ALL Build and Development Packages
apt install -y build-essential automake socat autoconf libtss2-tcti-tabrmd-dev dh-autoreconf libtasn1-dev libtss2-dev libcurl4-gnutls-dev python3-setuptools libtss2-tcti-tabrmd0 libtss2-esys0 libtasn1-6-dev libtool tpm2-tools git-crypt libssl-dev gnutls-dev gnutls-bin libseccomp-dev iproute2 ssh gawk libjansson-dev mlocate libp11-dev patch libgnutls28-dev softhsm2 python3-twisted flex tpm2-initramfs-tool libglib2.0-dev libgmp-dev m4 net-tools libxml2-dev dpkg-dev expect binutils gettext bison debhelper gcc libjson-glib-dev librtlsdr-dev pkg-config libfuse-dev dh-exec libdevmapper-dev libdevmapper-event1.02.1 libdevmapper1.02.1 libfreetype-dev dh-buildinfo xz-utils liblzma-dev lzma-dev gnulib byacc libbison-dev libcap-dev libefiboot-dev libefivar-dev

systemctl enable --now ssh

./setup_github_access.sh

git submodule update --init --recursive

# Network Security
ufw enable
ufw default deny incoming
ufw reload

cd hblock
make install
hblock
echo "59 * * * * /usr/local/bin/hblock" >> /var/spool/cron/crontabs/root
cd ..

# Malware Scanners
apt install -y chkrootkit rkhunter lynis checksec
rkhunter --propupd

# Virtualization
apt install -y virt-manager systemd-container
systemctl enable --now libvirtd
echo "Enter the name of the non-root admin user: "
read username

usermod -aG libvirt $username

# Remove unnecessary packages
apt remove -y avahi-daemon cups cups-browsed

# Yubikey
apt install libpam-u2f -y

# Kernel Security
cat sysctl.d/sysctl-baseline.conf >> /etc/sysctl.conf
sysctl -p

# Work needs to be done to determine which kernel parameters in sysctl.d/network.conf affect vpn 
# in any negative way. For now, don't set them until we are sure they will not affect vpn
# connections in any negative way.
echo "Will you be using a vpn on this host? (y/n): "
read use_vpn

if [ $use_vpn = "n" ]; then
	cat sysctl.d/network.conf >> /etc/sysctl.conf
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
cp -r apparmor/* /etc/apparmor.d/
apparmor_parser -r -T -W /etc/apparmor.d/pam_binaries /etc/apparmor.d/pam_roles

# Hardened Firefox user.js
echo "Enter the name of the user to install a hardened user.js for firefox for: "
read username

wget -O /home/$username/user.js https://raw.githubusercontent.com/arkenfox/user.js/master/user.js
chown $username:$username /home/$username/user.js
cp /home/$username/user.js /home/$username/.mozilla/firefox/*.default
mv /home/$username/user.js /home/$username/.mozilla/firefox/*.default-release


# Entropy
apt install -y jitterentropy-rngd
systemctl enable --now jitterentropy-rngd

apt install -y tpm2-abrmd
systemctl stop tpm2-abrmd

echo "Atempting to read random bytes from a tpm device with 'tpm2_getrandom --hex 16'. . ."
echo "If any errors occur, please disable tpm usage in /etc/systemd/system/rngd.service"
echo "See 'rngd --help and rngd -l for a list of devices that will as entropy sources on your device.\n"
echo $(tpm2_getrandom --hex 16)
systemctl enable --now tpm2-abrmd

# Export hardened compiler flags
export CPPFLAGS=$(dpkg-buildflags --get CPPFLAGS)
export CFLAGS=$(dpkg-buildflags --get CFLAGS)
export CXXFLAGS=$(dpkg-buildflags --get CXXFLAGS)
export LDFLAGS=$(dpkg-buildflags --get LDFLAGS)

cd rng-tools
./autogen.sh
./configure
make -j8
make install
find $(pwd) -name rngd.service -type f -exec sed -i 's/ExecStart=\/usr\/sbin\/rngd \-f/ExecStart=\/usr\/local\/sbin\/rngd \-r 1 \-r 2 \-r 0 \-W 4096/g' {} +
cp rngd.service /etc/systemd/system
systemctl enable --now rngd
cd ..

# Install swtpm
cd libtpms
./autogen.sh --with-openssl --prefix=/usr --with-tpm2
make -j8
make check
make install
cd ..

cd swtpm
./autogen.sh --with-openssl --prefix=/usr --libdir=/lib64
make -j8
make -j8 check
make install
cd ..

chmod -R 700 /root

echo "Do you want to install dell-recovery-bootloader? (y/n): "
read install_dell_recovery

if [ $install_dell_recovery = "y" ]; then
	apt install -y dell-recovery-bootloader 
fi


# Custom Secure Boot Key
echo "Would you like to customize your secure boot keys/certs? (y/n): "
echo "Note: if you select 'y', then the system packages for grub2 will"
echo "be removed, and the source code for grub2 will be installed instead.\n"
read custom_sb

if [ $custom_sb = "y" ]; then
	apt install -y efivar pesign

	cd efitools
	echo "Backing up old secure boot certificates in efivar submodule. . . \n"
	# Backup original secure boot keys certificats etc:
	mkdir ../old_secure_boot_keys
	efi-readvar -v PK -o ../old_secure_boot_keys/PK.old.esl
	efi-readvar -v KEK -o ../old_secure_boot_keys/KEK.old.esl
	efi-readvar -v db -o ../old_secure_boot_keys/db.old.esl
	efi-readvar -v dbx -o ../old_secure_boot_keys/dbx.old.esl
	chmod -R 0400 ../old_secure_boot_keys
	
	make clean
	make all
	rm LockDown*efi LockDown.so LockDown.o
	

	# Now create the keys:
	openssl req -new -x509 -newkey rsa:2048 -subj "/CN=PK/" -keyout PK.key -out PK.crt -days 3650 -nodes -sha256
	openssl req -new -x509 -newkey rsa:2048 -subj "/CN=KEK/" -keyout KEK.key -out KEK.crt -days 3650 -nodes -sha256
	openssl req -new -x509 -newkey rsa:2048 -subj "/CN=DB/" -keyout DB.key -out DB.crt -days 3650 -nodes -sha256
	openssl req -new -x509 -newkey rsa:2048 -subj "/CN=DBX/" -keyout DBX.key -out DBX.crt -days 3650 -nodes -sha256
	
	cert-to-sig-list PK.crt PK.esl
	sign-efi-sig-list -k PK.key -c PK.crt PK PK.esl PK.auth
	
	cert-to-sig-list KEK.crt KEK.esl
	sign-efi-sig-list -k KEK.key -c KEK.crt KEK KEK.esl KEK.auth
	
	cert-to-sig-list DB.crt DB.esl
	sign-efi-sig-list -k DB.key -c DB.crt db DB.esl DB.auth
	
	cert-to-sig-list DBX.crt DBX.esl
	sign-efi-sig-list -k DBX.key -c DBX.crt dbx DBX.esl DBX.auth
	
	rm -f noPK.esl
	touch noPK.esl
	sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" -k PK.key -c PK.crt PK PK.esl PK.auth
	sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" -k PK.key -c PK.crt PK noPK.esl noPK.auth
	
	make install


	# Change key and cert permissions
	chmod 0600 PK*
	chmod 0600 noPK*
	chmod 0600 KEK*
	chmod 0600 DB*
	chmod 0600 DBX*
	

	# Sign efi binaries generated by efivar submodule:
	echo "Enter the path where you wish to sign and install new efi binaries: "
	echo "Examples: /boot/efi/EFI/ubuntu and /boot/efi/EFI/BOOT\n"
	read boot_dir
	cp /usr/share/efitools/efi/*.efi $efi_boot_dir
	
	echo "Please enter the directory where you would like your linux kernel(s) signed: "
	echo "Example: /boot"
	read boot_dir
	
	# Strip existing signitures
	echo "Would you like to strip existing signitures from efi binaries in $boot_dir before they are signed with the new keys? (y/n): "
	echo "Note: it is recommended not to do this until after you have verified that"
	echo "you can boot with the newly enrolled keys.\n"
	read strip_sig

	if [ $strip_sig = "y" ]; then
		find $boot_dir -name *.efi -type f | xargs -I "^" pesign --signature-number 0 --remove-signature -i "^"
		find $boot_dir -name *.efi -type f | xargs -I "^" sbverify --cert DB.crt "^"
		
		find $boot_dir -name *.EFI -type f | xargs -I "^" pesign --signature-number 0 --remove-signature -i "^"
		find $boot_dir -name *.EFI -type f | xargs -I "^" sbverify --cert DB.crt "^"
		
		find $boot_dir -name vmlinuz* -type f | xargs -I "^" pesign --signature-number 0 --remove-signature -i "^"
		find $boot_dir -name vmlinuz* -type f | xargs -I "^" sbverify --cert DB.crt "^"
	fi
	
	
	find $boot_dir -name *.efi -type f | xargs -I "^" sbsign --key DB.key --cert DB.crt --output "^" "^"
	find $boot_dir -name *.efi -type f | xargs -I "^" sbverify --cert DB.crt "^"
	
	find $boot_dir -name *.EFI -type f | xargs -I "^" sbsign --key DB.key --cert DB.crt --output "^" "^"
	find $boot_dir -name *.EFI -type f | xargs -I "^" sbverify --cert DB.crt "^"
	
	
	find $boot_dir -name vmlinuz* -type f | xargs -I "^" sbsign --key DB.key --cert DB.crt --output "^" "^"
	find $boot_dir -name vmlinuz* -type f | xargs -I "^" sbverify --cert DB.crt "^"
	
	UpdateVars dbx DBX.auth
	UpdateVars db DB.auth
	UpdateVars KEK KEK.auth
	UpdateVars PK PK.auth
	
	echo "Would you like to copy your keys to $efi_boot_dir for uefi enrollment"
	echo "in UEFI firmware settings? (y/n): "
	echo "\n"
	read cpy_keys
	
	if [ $cpy_keys = "y" ]; then
		cp *.cer $efi_boot_dir
		cp *.auth $efi_boot_dir
		cp *.esl $efi_boot_dir
		cp *.crt $efi_boot_dir
		cp *.key $efi_boot_dir
	fi
	
	cd ..
	
fi

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
