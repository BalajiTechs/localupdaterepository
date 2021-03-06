#!/bin/bash
########################################################################################
# This script will setup local update repository on this machine(Ubuntu-Xenail) for CentOS 7, RHEL 7,
# Amazon Linux2, Ubuntu Xenail and SUSE/openSuSE 12. This script assumes that
# 1. Host machine is a Ubuntu 1604 LTS
# 2. 150 GB space on disk
# 3. Intenet connection
# 4. root user access(to run this script).
# 5. A stable fqdn. a volatile fqdn may break your clients in the sense that they
#	may not be able to know where you are soon after your fqdn changes
#
# Ref: https://estl.tech/host-your-own-yum-and-apt-repository-4ba8350eeda1
#
# Usage(run as root user)
# ./setup-local-repo.bash <base_dir> e.g. ./setup-local-repo.bash /data/repo_base/
########################################################################################

#local_repo_fqdn=`curl http://169.254.169.254/latest/meta-data/public-hostname`
local_repo_fqdn=`hostname -f`
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
tmp_dir="/tmp/local_repo_tmp"

#We also need suse12 repo url
suse12_update_mirror_url="http://download.opensuse.org/update/leap/15.0/oss/"

#create temp directory for all the needs
mkdir -p $tmp_dir

#We cannot procceed unless we have repo base dir
function error_exit
{
  echo "$1" 1>&2
  echo "Usage: ./$0 <repo base directory>" 1>&2
  exit 1
}

#This is where all your repo will be mirrored. Make sure that this is large enough to handle 
#all the repo data
repo_base=$1
if [ ! $repo_base ]
then
  error_exit "please provide base directory for repositories!"
fi

apt_mirror_dir=$repo_base/apt-mirror
suse_mirror_dir=$repo_base/zypper
centos_mirror_dir=$repo_base/yum-mirror/centos
centos_os_mirror_dir=$centos_mirror_dir/os/x86_64
centos_updates_mirror_dir=$centos_mirror_dir/updates/x86_64
centos_extras_mirror_dir=$centos_mirror_dir/extras/x86_64

#this should be either static or a regex so that even if fqdn changes we no need to restart nginx again
#nginx_server_name=

function install_deps
{
	#Update all repositories cache
	apt update
	#We need yum utilities to setup yum repository and do mirroring of online yum mirros
	apt install -y yum-utils
	#Using yum to install epel-release because it is availale in yum repo only
	yum install -y epel-release
	apt install -y createrepo rsync apt-mirror
	#nginx for hosting http repos
	apt install -y nginx
	
	#create a empty repo_sync cron
	cat >> $tmp_dir/repo_sync << EOL
#!/bin/bash
#this cron updates all local repository hosted on the server.
#this is autogenerated. Please consult the admin before changing anything in here
EOL
}

#Ubuntu provides four different software repositories, all of them official 
#— Main, Restricted, Universe, and Multiverse. 
#Main and Restricted are fully supported by Canonical
#Universe and Multiverse don’t receive the support you might expect.
function setup_apt_repository
{
	echo "Setting up apt-mirror in $repo_base"
	
	mkdir -v -p $apt_mirror_dir	
	mv -v  /etc/apt/mirror.list /etc/apt/mirror.list_bkp 
	ln -s $apt_mirror_dir/mirror/archive.ubuntu.com/ubuntu /var/www/ubuntu
	echo "Creating mirror list of only essential repos"
	cat > /etc/apt/mirror.list << EOL
set base_path $apt_mirror_dir
set nthreads 20
set _tilde 0

deb http://archive.ubuntu.com/ubuntu xenial main
deb http://archive.ubuntu.com/ubuntu xenial-security main
deb http://archive.ubuntu.com/ubuntu xenial-updates main

clean http://archive.ubuntu.com/ubuntu

EOL
	
	#Create entry in repo_sync file to mirror the repo here
	echo "Adding entry in repo_sync file"
	cat >> $tmp_dir/repo_sync << EOL
# Sync Ubuntu repos . See /etc/apt/mirror.list file for the mirrored repos
apt-mirror

EOL
	
}

function setup_suse_repository
{
	echo "Setting up zypper mirror in $repo_base"

	mkdir -v -p $suse_mirror_dir
	ln -s $suse_mirror_dir /var/www/zypper

#Suse repo is yum based repo. so we can configure the same as we have done for centos or AmazonLinux2
	cat >> /etc/yum.repos.d/opensuse.repo << EOL
[suse12-update]
#OpenSUSE Leap 15 is equvalent to SLES/SUSE 12
name=Suse12 Update Repository
baseurl=$suse12_update_mirror_url
gpgcheck=0
report_instanceid=no
EOL

	cat >> $tmp_dir/repo_sync << EOL
#sync opensuse repos here
reposync -c /etc/yum/yum.conf -n -d -g comps.xml --download-metadata --norepopath -r suse12-update --download_path=$suse_mirror_dir
#create repo database
createrepo -v --update --workers=4 $suse_mirror_dir
cd  $suse_mirror_dir;gunzip *updateinfo.xml.gz;mv *updateinfo.xml repodata/
modify $suse_mirror_dir/repodata/*updateinfo.xml $suse_mirror_dir/repodata
EOL
}

function setup_centos_repository
{
	echo "Setting up yum mirror repo in $repo_base"
	
	mkdir -p $centos_os_mirror_dir $centos_extras_mirror_dir $centos_updates_mirror_dir
	ln -s $centos_mirror_dir /var/www/centos
	
	#This scripts generate updateinfo.xml file from xml file containing the errata and advistory information
	cp $cur_dir/generate_updateinfo.py /usr/bin/
	chmod +x /usr/bin/generate_updateinfo.py
	
	
#I have disable gpgcheck since i am not creating rpm-gpg-key.
#gpgcheck=0 because EPEL has many packages with missing GPG keys. 
#Enabling gpgcheck will result in offending packages being downloaded 
#and deleted immediately at each sync.
	cat > /etc/yum/repos.d/centos.repo << EOL
[os]
name=CentOS-7 - Base
baseurl=http://mirror.centos.org/centos/7/os/x86_64
gpgcheck=0

[updates]
name=CentOS-7 - Updates
baseurl=http://mirror.centos.org/centos/7/updates/x86_64
gpgcheck=0

#additional packages that may be useful
[extras]
name=CentOS-7 - Extras
baseurl=http://mirror.centos.org/centos/7/extras/x86_64
gpgcheck=0
EOL

#add above repo to sync in repo_sync file
	cat >> $tmp_dir/repo_sync << EOL
# Sync CentOS and EPEL repos
reposync -c /etc/yum/yum.conf -n -d -g comps.xml --download-metadata --norepopath -r os --download_path=$centos_os_mirror_dir
# Build base packages metadata
createrepo --update --workers=4 $centos_os_mirror_dir/

reposync -c /etc/yum/yum.conf -n -d --download-metadata --norepopath -r updates --download_path=$centos_updates_mirror_dir
# Build update packages metadata
createrepo --update --workers=4 $centos_updates_mirror_dir/

reposync -c /etc/yum/yum.conf -n -d --download-metadata --norepopath -r extras --download_path=$centos_extras_mirror_dir
# Build extra packages metadata
createrepo --update --workers=4 $centos_extras_mirror_dir/

#Retrieve latest errata details
wget https://cefs.steve-meier.de/errata.latest.xml -p $tmp_dir

#Generate updateinfo.xml file from errata.latest.xml file.
generate_updateinfo.py errata.latest.xml --release=7 --destination=$tmp_dir

#Above script creates updateinfo.xml file in $tmp_dir/updateinfo-7 folder.
#We need to modify repodata with the generated updateinfo xml file
modifyrepo $tmp_dir/updateinfo-7/updateinfo.xml $centos_os_mirror_dir/repodata
modifyrepo $tmp_dir/updateinfo-7/updateinfo.xml $centos_updates_mirror_dir/repodata
modifyrepo $tmp_dir/updateinfo-7/updateinfo.xml $centos_extras_mirror_dir/repodata

EOL
}


function setup_rsync_mirror_cron
{
	echo "Creating weekly cron in /etc/cron.weekly folder to sync the online mirror repos on local"
	mv $tmp_dir/repo_sync /etc/cron.weekly/update_local_repo
	chmod 750 /etc/cron.weekly/update_local_repo
	#Uncomment to start mirroring of packages immediately
	#/etc/cron.weekly/update_local_repo
	echo "Creating link to repo_sync executable in /usr/bin"
	ln -s /etc/cron.weekly/update_local_repo /usr/bin/update_local_repo
	
}

function setup_nginx
{
	cat > /etc/nginx/sites-available/localrepo-site << EOL
server {
  listen 80;
  server_name *.amazonaws.com;
  gzip off;
  autoindex on;
  access_log /var/log/nginx/repo-access.log;
  root /var/www;
}
EOL
	ln -f -s /etc/nginx/sites-enabled/localrepo-site /etc/nginx/sites-available/localrepo-site 
	systemctl restart nginx
}

#Procedure to update files required by client to active this repo as their default repo
#A script is available that automatically idenfies the distro and configure them to use this local repository
function update_client_files
{
	echo "Copy enable_local_repo.bash on client machine"
	echo "Execute" " enable_local_repo.bash $local_repo_fqdn " "command on client machine to enable this repo"
}

function print_details
{
echo "-----------------------------------------------------------------------------------------------"
echo "Your local repo is Active now. If 80 port is not enable for public access please enable the same"
echo "-----------------------------------------------------------------------------------------------"
echo "You can browse the repo catalogue on below urls"
echo -e "\t\tUbuntu : http://$local_repo_fqdn/ubuntu"
echo "-----------------------------------------------------------------------------------------------"
echo "\t\tCentOS/RHEL : http://$local_repo_fqdn/centos"
echo "-----------------------------------------------------------------------------------------------"
echo "\t\tSLES/SUSE : http://$local_repo_fqdn/zypper"
echo "-----------------------------------------------------------------------------------------------"

echo "Note: Please execute command 'update_local_repo' to start syncing the online repositories to local"
echo "-----------------------------------------------------------------------------------------------"
}

#start creating the local repo
install_deps
setup_apt_repository
setup_centos_repository
#Creating mirror for RHEL require active subscription to that repo. rhel clients will sync from centos only.
#setup_rhel_repository 
setup_suse_repository
setup_rsync_mirror_cron
setup_nginx
print_details
