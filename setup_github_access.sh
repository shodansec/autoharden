#!/usr/bin/sh

echo "Enter your github username:"
read github_username

echo "Enter the email used with your github account:"
read github_email

git config --global user.name "$github_username"
git config --global user.email "$github_email"
git config --global credential.username "$github_username"


gpg --default-new-key-algo rsa4096 --gen-key

gpg --list-secret-keys --keyid-format=long

echo "Enter the short number after 'sec   rsa4096/':"
echo "\n"

read gpgtoken

git config --global user.signingkey $gpgtoken

if [ -r ~/.bash_profile ]; then echo 'export GPG_TTY=$(tty)' >> ~/.bash_profile; \
  else echo 'export GPG_TTY=$(tty)' >> ~/.profile; fi

git config --global commit.gpgsign true

echo "Enter the following gpg key to your github account:"
echo "\n"

gpg --armor --export $gpgtoken


ssh-keygen -t rsa -C "$github_email" -f ~/.ssh/id_rsa
ssh-add ~/.ssh/ida_rsa
eval "$(ssh-agent -s)"

echo "Add the following public ssh key to your github profile:"
echo "\n"
cat ~/.ssh/id_rsa.pub

git submodule update --init --recursive
