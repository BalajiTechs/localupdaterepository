#!/bin/bash
###########################  ALWAYS RUN THIS SCRIPT AS ROOT  ###########################
#This script enables any local repositories on the host. 
#For this to work, one must supply the fully qualified domain name of the repo server
# Note: Update local_repo_fqdn variable. for e.g. if your repo server fqdn is example.aws.amazon.com then change
# local_repo_fqdn=example.aws.amazon.com
# 
#Usage: This scipt can directly be passed to RUN utility in SSM. 
#
###########################  ALWAYS RUN THIS SCRIPT AS ROOT  ###########################


#We cannot procceed unless we have repo server fqdn
function error_exit
{
  echo "$1" 1>&2
  echo "Usage: ./enable_local_repo.bash <local_repo_hostname>" 1>&2
  exit 1
}

#I have hardcoded the fqdn here. Change if this fqdn chagnes
local_repo_fqdn="ec2-18-206-162-221.compute-1.amazonaws.com"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
OS=""


function enable_amzn_repo
{
	echo "-----------------------------------------------------------"
	echo "enabling local amazon repo on this machine"
	cd /etc/yum.repos.d
	for f in *.repo; do mv -- "$f" "${f%.repo}.bkp"; done
	cat > /etc/yum.repos.d/local-amzn-core.repo <<EOL 
####local-amzn-core repo#####
[amzn2-core-local]
name=Amazon Linux 2 core repository
baseurl=http://$local_repo_fqdn/amzn2/
gpgcheck=0
enabled=1
report_instanceid=no
EOL
echo "-----------------------------------------------------------"	
	echo "Cleaning old cache"
	rm -rf /var/cache/yum
	yum clean all
echo "-----------------------------------------------------------"
	echo "lets check updates from our own repo"
	yum check-update
	
	echo "Lets check updateinfo summary"
	yum updateinfo list
echo "-----------------------------------------------------------"
}

#This works for both Centos and RHEL
function enable_yum_repo
{
	echo "-----------------------------------------------------------"
	echo "enabling local yum repo on this machine"
	cd /etc/yum.repos.d
	for f in *.repo; do mv -- "$f" "${f%.repo}.bkp"; done
	cat > /etc/yum.repos.d/local-yum.repo <<EOL 
####local-yum-repo#####
[base]
name=CentOS-Base
baseurl=http://$local_repo_fqdn/centos/7/os/x86_64/
gpgcheck=0

#released updates
[updates]
name=CentOS-Updates
baseurl=http://$local_repo_fqdn/centos/7/updates/x86_64/
gpgcheck=0

#additional packages that may be useful
[extras]
name=CentOS-Extras
baseurl=http://$local_repo_fqdn/centos/7/extras/x86_64/
gpgcheck=0
EOL
echo "-----------------------------------------------------------"	
	echo "Cleaning old cache"
	rm -rf /var/cache/yum/*
	yum clean all
echo "-----------------------------------------------------------"
	echo "lets check updates from our own repo"
	yum check-update
echo "-----------------------------------------------------------"
echo "Lets check updateinfo summary"
	yum updateinfo list
echo "-----------------------------------------------------------"
}

function enable_apt_repo
{
	echo "enabling local apt repo on this machine"
	mv /etc/apt/sources.list /etc/apt/sources.list_backup
	cat > /etc/apt/sources.list << EOL
deb [trusted=yes] http://$local_repo_fqdn/ubuntu/ xenial main 
deb [trusted=yes] http://$local_repo_fqdn/ubuntu/ xenial-updates main
deb [trusted=yes] http://$local_repo_fqdn/ubuntu/ xenial-security main
EOL
	echo "Cleaning old cache"
	apt-get clean
	echo "lets check updates from our own repo"
	apt update
	echo "Upgradable pacakges"
	apt list --upgradable
	
	echo "Severity details for each packages"
	aptitude search -F '%p %P %s %t %V#' '~U'
}

function enable_zypper_repo
{
	echo "enabling local zypper repo on this machine"
	zypper lr --export /var/tmp/backup.repo
	line_count=$(zypper repos |wc -l)
	total_repo=`expr $line_count - 5`
	for ((n=1;n<=$total_repo;n++))
    do
           repo_to_delete=$(zypper repos $n |grep Name|awk '{ print $3 }')
           echo "disabling repo $repo_to_delete"
           zypper rr $n
    done
	echo "moving and enable smt services to /var/tmp"
	mv /etc/zypp/services.d/*.service /var/tmp/
	echo "adding our own zypper repo"
	zypper ar http://$local_repo_fqdn/zypper/base/ local-suse-repo
	
	#now due to vendor stickyness in zypper we have to add a specific line in zypp.conf files
	# See https://en.opensuse.org/SDB:Vendor_change_update
	echo "solver.allowVendorChange = true" >> /etc/zypp/zypp.conf
	echo "refreshing repo cache"
	zypper refresh
	echo "Lets check if this machine has any updates from our own repo"
	zypper list-updates
	
	echo "Lets check patch informations"
	zypper list-patches
}

#I must know Distro Name of this, otherwise how will i get to know which repo to enable
#I am checking files which respective distro uses to store the name of Distribution
function get_os_release
{
	if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    ...
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    ...
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
fi
}

get_os_release
echo "OS Distribution is  $OS "

if [[ $OS = *"Ubuntu"* ]]; then
	enable_apt_repo
elif [[ $OS = *"CentOS"* ]]; then
	enable_yum_repo
elif [[ $OS = *"Amazon"* ]]; then
	enable_amzn_repo
elif [[ $OS = *"Red Hat"* ]]; then
	enable_yum_repo
elif [[ $OS = *"SLES"* ]]; then
	enable_zypper_repo
else
	echo "OS $OS not supported"
fi
echo "-----------------------------------------------------------"
echo -e "\t\t you are all set"
echo "-----------------------------------------------------------"