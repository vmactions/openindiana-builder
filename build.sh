#!/usr/bin/env bash

set -ex


_conf="$1"

if [ -z "$_conf" ] ; then
  echo "Please give the conf file"
  exit 1
fi


. "$_conf"


##############################################################
osname="$VM_OS_NAME"
ostype="$VM_OS_TYPE"
sshport=$VM_SSH_PORT


opts="$VM_OPTS"

vboxlink="${SEC_VBOX:-$VM_VBOX_LINK}"


vmsh="$VM_VBOX"


export VM_OS_NAME
export VM_RELEASE
export VM_OCR
export VM_DISK
export VM_ARCH


##############################################################


waitForText() {
  _text="$1"
  $vmsh waitForText $osname "$_text"
}

#keys splitted by ;
#eg:  enter
#eg:  down; enter
#eg:  down; up; tab; enter


inputKeys() {
  $vmsh input $osname "$1"
}



if [ ! -e "$vmsh" ] ; then
  echo "Downloading $vboxlink"
  wget -O "$vmsh" "$vboxlink"
fi

chmod +x "$vmsh"



$vmsh startWeb $osname "needOCR"


$vmsh setup "needOCR"

if ! $vmsh clearVM $osname; then
  echo "vm does not exists"
fi


if [ "$VM_ISO_LINK" ]; then
  $vmsh createVM  $VM_ISO_LINK $osname $ostype $sshport

  sleep 2

  if [ -e "hooks/installOpts.sh" ]; then
    echo "hooks/installOpts.sh"
    cat "hooks/installOpts.sh"
    . "hooks/installOpts.sh"
  else
    $vmsh  processOpts  $osname  "$opts"
  
    echo "sleep 60 seconds. just wait"
    sleep 60
  
    if $vmsh isRunning $osname; then
      if ! $vmsh shutdownVM $osname; then
        echo "shutdown error"
      fi
      if ! $vmsh destroyVM $osname; then
        echo "destroyVM error"
      fi
    fi
  fi

  while $vmsh isRunning $osname; do
    sleep 5
  done

elif [ "$VM_VHD_LINK" ]; then
  if [ ! -e "$osname.qcow2" ]; then
    if [ ! -e "$osname.qcow2.xz" ]; then
      $vmsh download "$VM_VHD_LINK" $osname.qcow2.xz
    fi
    xz -d -T 0 --verbose  "$osname.qcow2.xz"
  fi

  $vmsh createVMFromVHD $osname $ostype $sshport

  sleep 5

else
  echo "no VM_ISO_LINK or VM_VHD_LINK, can not build."
  exit 1
fi


echo "VM image size immediately after install:"
ls -lh


start_and_wait() {
  $vmsh startVM $osname
  sleep 2
  if [ -e "hooks/waitForLoginTag.sh" ]; then
    echo "hooks/waitForLoginTag.sh"
    cat "hooks/waitForLoginTag.sh"
    . "hooks/waitForLoginTag.sh"
  else
    waitForText "$VM_LOGIN_TAG"
  fi

  sleep 3
}

shutdown_and_wait() {
  ssh $osname  "$VM_SHUTDOWN_CMD"

  sleep 30

  if $vmsh isRunning $osname; then
    if ! $vmsh shutdownVM $osname; then
      echo "shutdown error"
    fi
  fi

  while $vmsh isRunning $osname; do
    sleep 5
  done
}

restart_and_wait() {
  shutdown_and_wait
  start_and_wait
}

###############################################

start_and_wait

inputKeys "string root; enter; sleep 1;"
if [ "$VM_ROOT_PASSWORD" ]; then
  inputKeys "string $VM_ROOT_PASSWORD ; enter"
fi
inputKeys "enter"
sleep 2


if [ ! -e ~/.ssh/id_rsa ] ; then 
  ssh-keygen -f  ~/.ssh/id_rsa -q -N "" 
fi

cat enablessh.txt >enablessh.local


#add ssh key twice, to avoid bugs.
echo "echo '$(base64 -w 0 ~/.ssh/id_rsa.pub)' | openssl base64 -d >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local

echo "echo '$(cat ~/.ssh/id_rsa.pub)' >>~/.ssh/authorized_keys" >>enablessh.local
echo "" >>enablessh.local


echo >>enablessh.local
echo "chmod 600 ~/.ssh/authorized_keys">>enablessh.local
echo "exit">>enablessh.local
echo >>enablessh.local


$vmsh inputFile $osname enablessh.local


###############################################################

$vmsh addSSHHost  $osname


ssh $osname sh <<EOF
echo 'StrictHostKeyChecking=no' >.ssh/config

echo "Host host" >>.ssh/config
echo "     HostName  192.168.122.1" >>.ssh/config
echo "     User runner" >>.ssh/config
echo "     ServerAliveInterval 1" >>.ssh/config

EOF

###############################################################

if [ -e "hooks/postBuild.sh" ]; then
  echo "hooks/postBuild.sh"
  cat "hooks/postBuild.sh"
  ssh $osname sh<"hooks/postBuild.sh"

  # Reboot here, possible there were system updates done that need
  # a reboot to take effect before more operations can be done
  restart_and_wait
fi


output="$osname-$VM_RELEASE"
if [ "$VM_ARCH" ]; then
  output="$osname-$VM_RELEASE-$VM_ARCH"
fi

ssh $osname 'cat ~/.ssh/id_rsa.pub' >$output-id_rsa.pub



#upload reboot.sh
if [ -e "hooks/reboot.sh" ]; then
  echo "hooks/reboot.sh"
  cat "hooks/reboot.sh"
  scp hooks/reboot.sh $osname:/reboot.sh
else
  ssh "$osname" "cat - >/reboot.sh" <<EOF
sleep 5
ssh host sh <<END
env | grep SSH_CLIENT | cut -d = -f 2 | cut -d ' ' -f 1 >$osname.rebooted

END

EOF
fi

#set cronjob
ssh "$osname" sh <<EOF
chmod +x /reboot.sh
cat /reboot.sh
if uname -a | grep SunOS >/dev/null; then
crontab -l | {  cat;  echo "* * * * * /reboot.sh";   } | crontab --
else
crontab -l | {  cat;  echo "@reboot /reboot.sh";   } | crontab -
fi
crontab -l

EOF


# Install any requested packages
if [ "$VM_PRE_INSTALL_PKGS" ]; then
  echo "$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
  ssh $osname sh <<<"$VM_INSTALL_CMD $VM_PRE_INSTALL_PKGS"
fi

if [ -e "hooks/finalize.sh" ]; then
  echo "hooks/finalize.sh"
  cat "hooks/finalize.sh"
  ssh $osname sh<"hooks/finalize.sh"
fi

# Done!
shutdown_and_wait

##############################################################

if [ "$VM_ISO_LINK" ]; then
  echo "Clean up ISO for more space"
  sudo rm -f ${osname}.iso
fi

echo "contents of home directory:"
ls -lah

echo "free space:"
df -h



ova="$output.qcow2"
echo "Exporting $ova"
$vmsh exportOVA $osname "$ova"

cp ~/.ssh/id_rsa  $output-host.id_rsa

echo "contents after export:"
ls -lah


##############################################################

echo "Checking the packages: $VM_RSYNC_PKG $VM_SSHFS_PKG"

if [ -z "$VM_RSYNC_PKG$VM_SSHFS_PKG" ]; then
  echo "skip"
else
  $vmsh addSSHAuthorizedKeys $output-id_rsa.pub
  $vmsh startVM $osname
  $vmsh waitForVMReady $osname
  if [ "$VM_RSYNC_PKG" ]; then
    ssh $osname sh <<<"$VM_INSTALL_CMD $VM_RSYNC_PKG"
  fi
  if [ "$VM_SSHFS_PKG" ]; then
    ssh $osname sh <<<"$VM_INSTALL_CMD $VM_SSHFS_PKG"
  fi
fi


